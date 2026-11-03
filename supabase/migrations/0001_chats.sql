-- TL;DR schema, part 1: people, group chats, invite codes, messages.
--
-- Security model: Row Level Security is the boundary. The iOS app ships the
-- publishable key, so every rule a member must not break lives here:
--   * you only ever see chats you belong to, their members and messages;
--   * you can only post as yourself, into a chat you belong to;
--   * creating, joining, leaving and read cursors go through security-definer
--     RPCs, so clients get no direct write access to chats or chat_members.
-- Members see the chat's whole history (that is the point of "catch me up").
--
-- Pattern adapted from AurariaGO's group chats (definer helpers called from
-- policies, a hygiene trigger, server-kept summary columns), slimmed down.

-- ---------------------------------------------------------------------------
-- Profiles: one per auth user, created by trigger on sign-up.

create table public.profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  display_name text not null
    constraint profiles_display_name_check
    check (char_length(display_name) between 1 and 30 and display_name = btrim(display_name)),
  created_at   timestamptz not null default now()
);

create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare nm text := left(btrim(split_part(coalesce(new.email, 'friend'), '@', 1)), 30);
begin
  if nm = '' then nm := 'friend'; end if;
  insert into public.profiles (id, display_name) values (new.id, nm)
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Chats, members, messages.

create table public.chats (
  id                   uuid primary key default gen_random_uuid(),
  name                 text not null
    constraint chats_name_check
    check (char_length(name) between 1 and 50 and name = btrim(name)),
  invite_code          text not null unique
    constraint chats_invite_code_check check (invite_code ~ '^[A-HJ-NP-Z2-9]{6}$'),
  created_by           uuid references public.profiles(id) on delete set null,
  created_at           timestamptz not null default now(),
  member_count         integer not null default 0 check (member_count >= 0),
  last_message_at      timestamptz,
  last_message_preview text,
  last_message_sender  uuid references public.profiles(id) on delete set null
);

create table public.chat_members (
  chat_id      uuid not null references public.chats(id) on delete cascade,
  user_id      uuid not null references public.profiles(id) on delete cascade,
  joined_at    timestamptz not null default now(),
  last_read_at timestamptz not null default now(),
  primary key (chat_id, user_id)
);

create index chat_members_user_idx on public.chat_members (user_id);

create table public.messages (
  id         uuid primary key default gen_random_uuid(),
  chat_id    uuid not null references public.chats(id) on delete cascade,
  sender     uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  body       text not null
    constraint messages_body_check check (char_length(body) between 1 and 2000),
  created_at timestamptz not null default now()
);

create index messages_chat_time_idx on public.messages (chat_id, created_at desc);
create index messages_sender_idx    on public.messages (sender);

-- Failed invite-code guesses, so codes can't be brute-forced.
create table public.join_attempts (
  user_id    uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now()
);
create index join_attempts_user_time_idx on public.join_attempts (user_id, created_at desc);

alter table public.profiles      enable row level security;
alter table public.chats         enable row level security;
alter table public.chat_members  enable row level security;
alter table public.messages      enable row level security;
alter table public.join_attempts enable row level security;

revoke all on public.profiles, public.chats, public.chat_members, public.messages, public.join_attempts
  from public, anon, authenticated;

grant select on public.profiles, public.chats, public.chat_members, public.messages to authenticated;
grant update (display_name) on public.profiles to authenticated;
-- id is client-chosen so an optimistic bubble can be matched to its row.
grant insert (id, chat_id, body) on public.messages to authenticated;

-- ---------------------------------------------------------------------------
-- Helpers the policies call. Definer, so a policy on chat_members can ask
-- about chat_members without recursing; each only answers about the caller.

create or replace function public.is_chat_member(p_chat uuid)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (select 1 from public.chat_members
                  where chat_id = p_chat and user_id = auth.uid());
$$;

create or replace function public.shares_chat_with(p_user uuid)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (select 1
                   from public.chat_members a
                   join public.chat_members b on b.chat_id = a.chat_id
                  where a.user_id = auth.uid() and b.user_id = p_user);
$$;

revoke execute on function public.is_chat_member(uuid), public.shares_chat_with(uuid) from public, anon;
grant execute on function public.is_chat_member(uuid), public.shares_chat_with(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Policies.

create policy profiles_select on public.profiles
  for select to authenticated
  using (id = auth.uid() or public.shares_chat_with(id));

create policy profiles_update_self on public.profiles
  for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

create policy chats_select_member on public.chats
  for select to authenticated
  using (public.is_chat_member(id));

create policy chat_members_select_member on public.chat_members
  for select to authenticated
  using (public.is_chat_member(chat_id));

create policy messages_select_member on public.messages
  for select to authenticated
  using (public.is_chat_member(chat_id));

create policy messages_insert_member on public.messages
  for insert to authenticated
  with check (sender = auth.uid() and public.is_chat_member(chat_id));

-- ---------------------------------------------------------------------------
-- Hygiene: server time, trimmed text, a sane send rate.

create or replace function public.enforce_message_hygiene()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  new.created_at := now();
  new.body := btrim(new.body);
  if new.body = '' then
    raise exception 'Message is empty';
  end if;
  -- Seeding/demo scripts run as service_role or postgres and skip the limit.
  if auth.uid() is not null
     and (select count(*) from public.messages
           where sender = new.sender and created_at > now() - interval '10 seconds') >= 20 then
    raise exception 'Sending too fast';
  end if;
  return new;
end;
$$;

create trigger messages_hygiene
  before insert on public.messages
  for each row execute function public.enforce_message_hygiene();

-- Summary line on the chat, and the sender has read their own message.
create or replace function public.apply_message()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  update public.chats
     set last_message_at      = new.created_at,
         last_message_preview = left(new.body, 140),
         last_message_sender  = new.sender
   where id = new.chat_id;
  update public.chat_members
     set last_read_at = new.created_at
   where chat_id = new.chat_id and user_id = new.sender and last_read_at < new.created_at;
  return new;
end;
$$;

create trigger messages_apply
  after insert on public.messages
  for each row execute function public.apply_message();

create or replace function public.apply_member_change()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    update public.chats set member_count = member_count + 1 where id = new.chat_id;
    return new;
  end if;
  update public.chats set member_count = greatest(member_count - 1, 0) where id = old.chat_id;
  -- Last one out deletes the chat and its messages.
  if not exists (select 1 from public.chat_members where chat_id = old.chat_id) then
    delete from public.chats where id = old.chat_id;
  end if;
  return old;
end;
$$;

create trigger chat_members_count
  after insert or delete on public.chat_members
  for each row execute function public.apply_member_change();

-- ---------------------------------------------------------------------------
-- RPCs.

-- Six characters, no 0/O/1/I, from gen_random_uuid's random bytes.
create or replace function public.new_invite_code()
returns text
language plpgsql volatile
set search_path = public
as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  raw bytea;
  code text;
begin
  loop
    raw := uuid_send(gen_random_uuid());
    code := '';
    for i in 0..5 loop
      code := code || substr(alphabet, (get_byte(raw, i) % 32) + 1, 1);
    end loop;
    exit when not exists (select 1 from public.chats where invite_code = code);
  end loop;
  return code;
end;
$$;

create or replace function public.create_chat(p_name text)
returns public.chats
language plpgsql security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  nm text := nullif(regexp_replace(btrim(coalesce(p_name, '')), '\s+', ' ', 'g'), '');
  c public.chats;
begin
  if me is null then raise exception 'Not signed in'; end if;
  if nm is null then raise exception 'Give the chat a name'; end if;
  if char_length(nm) > 50 then raise exception 'Chat names can be up to 50 characters'; end if;
  if (select count(*) from public.chats
       where created_by = me and created_at > now() - interval '1 day') >= 20 then
    raise exception 'Too many new chats today';
  end if;
  insert into public.chats (name, invite_code, created_by)
  values (nm, public.new_invite_code(), me)
  returning * into c;
  insert into public.chat_members (chat_id, user_id) values (c.id, me);
  select * into c from public.chats where id = c.id;  -- member_count after the trigger
  return c;
end;
$$;

-- Join with an invite code. New members start "unread" from the beginning,
-- so their first Catch me up covers the whole history.
create or replace function public.join_chat(p_code text)
returns public.chats
language plpgsql security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  code text := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
  c public.chats;
begin
  if me is null then raise exception 'Not signed in'; end if;
  if (select count(*) from public.join_attempts
       where user_id = me and created_at > now() - interval '1 hour') >= 15 then
    raise exception 'Too many wrong codes. Try again in an hour.';
  end if;
  select * into c from public.chats where invite_code = code;
  if not found then
    -- Return instead of raising: a raise would roll back this counter row.
    -- The client reads an all-null row as "no chat with that code".
    insert into public.join_attempts (user_id) values (me);
    return null;
  end if;
  if (select member_count from public.chats where id = c.id) >= 64 then
    raise exception 'That chat is full';
  end if;
  insert into public.chat_members (chat_id, user_id, last_read_at)
  values (c.id, me, c.created_at)
  on conflict (chat_id, user_id) do nothing;
  select * into c from public.chats where id = c.id;
  return c;
end;
$$;

create or replace function public.leave_chat(p_chat uuid)
returns void
language sql security definer
set search_path = public
as $$
  delete from public.chat_members where chat_id = p_chat and user_id = auth.uid();
$$;

-- Moves the caller's read cursor forward (never back).
create or replace function public.mark_read(p_chat uuid, p_at timestamptz default null)
returns void
language sql security definer
set search_path = public
as $$
  update public.chat_members
     set last_read_at = greatest(last_read_at, least(coalesce(p_at, now()), now()))
   where chat_id = p_chat and user_id = auth.uid();
$$;

-- The inbox: my chats, newest activity first, with unread counts.
create or replace function public.my_chats()
returns table (
  id uuid, name text, invite_code text, member_count integer,
  created_at timestamptz, last_message_at timestamptz,
  last_message_preview text, last_message_sender_name text,
  last_read_at timestamptz, unread_count integer
)
language sql stable security definer
set search_path = public
as $$
  select c.id, c.name, c.invite_code, c.member_count, c.created_at,
         c.last_message_at, c.last_message_preview, p.display_name,
         m.last_read_at,
         (select count(*)::int from public.messages x
           where x.chat_id = c.id and x.created_at > m.last_read_at and x.sender <> auth.uid())
    from public.chat_members m
    join public.chats c on c.id = m.chat_id
    left join public.profiles p on p.id = c.last_message_sender
   where m.user_id = auth.uid()
   order by coalesce(c.last_message_at, c.created_at) desc;
$$;

revoke execute on function public.new_invite_code(), public.handle_new_user(),
  public.enforce_message_hygiene(), public.apply_message(), public.apply_member_change()
  from public, anon, authenticated;
revoke execute on function public.create_chat(text), public.join_chat(text), public.leave_chat(uuid),
  public.mark_read(uuid, timestamptz), public.my_chats()
  from public, anon;
grant execute on function public.create_chat(text), public.join_chat(text), public.leave_chat(uuid),
  public.mark_read(uuid, timestamptz), public.my_chats()
  to authenticated;

-- ---------------------------------------------------------------------------
-- Realtime: new messages stream to members (Realtime applies the select policy).

alter publication supabase_realtime add table public.messages;
