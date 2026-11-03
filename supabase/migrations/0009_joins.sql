-- Ketchup schema, part 9: "Maya joined" in the thread (Nov 3, 2026). One
-- part, applied live as 0009_joins.
--
-- Joining a chat leaves one line in it, the way group chats say who came
-- in. The line is a messages row with kind = 'joined', from the person who
-- joined, so it pages, arrives over Realtime, stays on the phone and hides
-- behind a block like any message. The apps draw it as a small centered
-- "Maya joined"; catch-up shows it to Muse Spark as "[Maya joined]",
-- context it never summarizes or cites.
--   * Only the server writes one: join_chat for whoever joins, create_chat
--     for whoever starts the chat, create_chat_with for each person added.
--     Clients can't set kind (no insert grant on it), and the insert policy
--     takes only kind = 'text' besides, so nobody can post a join line, for
--     themselves or for anyone else.
--   * One per person per chat. Joining again after leaving moves the line
--     to now, so leaving and rejoining can't fill a thread; joining a chat
--     you're already in writes nothing.
--   * It isn't news. It never counts as unread (my_chats, and catch-up in
--     the edge function), never becomes the inbox's last message
--     (apply_message, my_chats when a block hides the last one,
--     delete_account), never moves the joiner's read cursor (a new member
--     still starts with the whole history unread), and never counts toward
--     or trips the send limit.
--   * Its body is the word "joined": an app from before this shows a plain
--     "joined" from that person instead of an empty bubble.
-- Nothing is backfilled: people already in a chat get no line. Additive for
-- the apps already out there, which read the columns they knew.

alter table public.messages
  add column kind text not null default 'text'
    constraint messages_kind_check check (kind in ('text', 'joined'));

-- A join line is words only.
alter table public.messages
  add constraint messages_joined_check check (kind = 'text' or image_path is null);

-- Members post text, as themselves, into their own chats. kind stays the
-- server's: clients have no insert grant on it, and this holds even if one
-- is ever added.
alter policy messages_insert_member on public.messages
  with check (sender = auth.uid() and kind = 'text' and public.is_chat_member(chat_id));

-- ---------------------------------------------------------------------------
-- The one way a join line is written, from the RPCs below (they run as the
-- table's owner). Clients can't call it.

create or replace function public.post_joined(p_chat uuid, p_user uuid)
returns void
language plpgsql
set search_path = public
as $$
begin
  delete from public.messages where chat_id = p_chat and sender = p_user and kind = 'joined';
  insert into public.messages (chat_id, sender, body, kind) values (p_chat, p_user, 'joined', 'joined');
end;
$$;

revoke execute on function public.post_joined(uuid, uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Triggers: 0006's hygiene and summary line, with join lines left out.

create or replace function public.enforce_message_hygiene()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  new.created_at := now();
  new.body := btrim(new.body);
  if new.body = '' and new.image_path is null then
    raise exception 'Message is empty';
  end if;
  if new.image_path is not null and not exists (
       select 1 from storage.objects where bucket_id = 'chat-media' and name = new.image_path) then
    raise exception 'Photo not uploaded';
  end if;
  -- Seeding/demo scripts run as service_role or postgres and skip the limit.
  -- A join line is the server's, not a send: it never counts or waits.
  if new.kind = 'text' and auth.uid() is not null
     and (select count(*) from public.messages
           where sender = new.sender and created_at > now() - interval '10 seconds'
             and kind = 'text') >= 20 then
    raise exception 'Sending too fast';
  end if;
  return new;
end;
$$;

create or replace function public.apply_message()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  -- A join line isn't news: the inbox line stays as it is, and so does the
  -- joiner's read cursor (a new member starts with everything unread).
  if new.kind <> 'text' then
    return new;
  end if;
  update public.chats
     set last_message_at      = new.created_at,
         last_message_preview = case
           when new.image_path is null then left(new.body, 140)
           when new.body = '' then '📷 Photo'
           else '📷 ' || left(new.body, 138)
         end,
         last_message_sender  = new.sender
   where id = new.chat_id;
  update public.chat_members
     set last_read_at = new.created_at
   where chat_id = new.chat_id and user_id = new.sender and last_read_at < new.created_at;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- The RPCs that put someone in a chat. Same as before, plus the line.

-- 0001's create_chat: the chat starts with its creator's line.
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
  perform public.post_joined(c.id, me);
  select * into c from public.chats where id = c.id;  -- member_count after the trigger
  return c;
end;
$$;

-- 0003's join_chat: a new member gets the line; someone already in doesn't.
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
  values (c.id, me, c.created_at - interval '1 millisecond')
  on conflict (chat_id, user_id) do nothing;
  if found then
    perform public.post_joined(c.id, me);
  end if;
  select * into c from public.chats where id = c.id;
  return c;
end;
$$;

-- 0007's create_chat_with: a line for each person it adds, after the
-- creator's (all at the same moment: the apps order them by id).
create or replace function public.create_chat_with(p_name text, p_people uuid[])
returns public.chats
language plpgsql security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  c public.chats;
  added uuid;
begin
  if me is null then raise exception 'Not signed in'; end if;
  if coalesce(array_length(p_people, 1), 0) > 63 then
    raise exception 'A chat holds up to 64 people';
  end if;
  select * into c from public.create_chat(p_name);
  for added in
    insert into public.chat_members (chat_id, user_id, last_read_at)
    select c.id, k.contact, c.created_at - interval '1 millisecond'
      from public.contacts k
     where k.owner = me
       and k.contact = any (coalesce(p_people, '{}'))
       and not exists (select 1 from public.blocks b
                        where (b.blocker = k.contact and b.blocked = me)
                           or (b.blocker = me and b.blocked = k.contact))
    on conflict (chat_id, user_id) do nothing
    returning user_id
  loop
    perform public.post_joined(c.id, added);
  end loop;
  select * into c from public.chats where id = c.id;
  return c;
end;
$$;

-- ---------------------------------------------------------------------------
-- Where a chat's messages are counted or quoted: text only.

-- 0007 part 5's inbox: unread counts and the line a block falls back to
-- skip join lines. Same columns, same speed (the speed check's busy account).
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
  with me as materialized (select auth.uid() as id),
       blocked as materialized (select public.my_blocked_ids() as ids)
  select c.id, c.name, c.invite_code, c.member_count, c.created_at,
         case when h.hidden then v.created_at else c.last_message_at end,
         case when h.hidden then v.preview else c.last_message_preview end,
         case when h.hidden then vp.display_name else p.display_name end,
         m.last_read_at,
         (select count(*)::int from public.messages x
           where x.chat_id = c.id and x.created_at > m.last_read_at and x.kind = 'text'
             and x.sender <> me.id and x.sender <> all (blocked.ids))
    from me
    cross join blocked
    join public.chat_members m on m.user_id = me.id
    join public.chats c on c.id = m.chat_id
    cross join lateral (
      select coalesce(c.last_message_sender = any (blocked.ids), false) as hidden) h
    left join lateral (
      select x.created_at, x.sender,
             case
               when x.image_path is null then left(x.body, 140)
               when x.body = '' then '📷 Photo'
               else '📷 ' || left(x.body, 138)
             end as preview
        from public.messages x
       where h.hidden and x.chat_id = c.id and x.kind = 'text' and x.sender <> all (blocked.ids)
       order by x.created_at desc
       limit 1) v on true
    left join public.profiles p on p.id = c.last_message_sender
    left join public.profiles vp on vp.id = v.sender
   order by coalesce(case when h.hidden then v.created_at else c.last_message_at end, c.created_at) desc;
$$;

-- 0007 part 3's delete_account: the inbox line it writes for the chats left
-- behind is their newest text, not someone's join line. Friends' saved
-- catch-ups that could have read anything of theirs still go, join lines
-- included.
create or replace function public.delete_account()
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  touched uuid[];
  files jsonb;
begin
  if me is null then raise exception 'Not signed in'; end if;

  select jsonb_build_object(
           'avatars', coalesce(jsonb_agg(o.name) filter (where o.bucket_id = 'avatars'), '[]'::jsonb),
           'chat-media', coalesce(jsonb_agg(o.name) filter (where o.bucket_id = 'chat-media'), '[]'::jsonb))
    into files
    from storage.objects o
   where (o.bucket_id = 'avatars'
          and (o.owner_id = me::text or (storage.foldername(o.name))[1] = me::text))
      or (o.bucket_id = 'chat-media' and o.owner_id = me::text);

  select coalesce(array_agg(distinct t.chat_id), '{}') into touched
    from (select chat_id from public.messages where sender = me
          union
          select chat_id from public.chat_members where user_id = me) t;

  delete from public.ai_briefs b
   where b.user_id <> me
     and b.chat_id = any (touched)
     and exists (select 1 from public.messages m
                  where m.chat_id = b.chat_id and m.sender = me and m.created_at <= b.until);

  delete from auth.users where id = me;

  update public.chats c
     set (last_message_at, last_message_preview, last_message_sender) =
         (select m.created_at,
                 case
                   when m.image_path is null then left(m.body, 140)
                   when m.body = '' then '📷 Photo'
                   else '📷 ' || left(m.body, 138)
                 end,
                 m.sender
            from public.messages m
           where m.chat_id = c.id and m.kind = 'text'
           order by m.created_at desc
           limit 1)
   where c.id = any (touched);

  return files;
end;
$$;
