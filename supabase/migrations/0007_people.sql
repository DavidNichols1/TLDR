-- Ketchup schema, part 7: people. Your account now; the people you block,
-- report and keep as contacts come in later parts of this file.
--
-- Applied live in parts, one apply_migration per slice of the people work,
-- each named 0007_people_<part>. This file is all of them, in order, so a
-- fresh project gets everything from one `supabase db push`:
--   0007_people_account          delete_account()
--   0007_people_account_photos   delete_account() previews a photo like apply_message
--   0007_people_blocks_reports   blocks, reports, the messages policy, my_chats
--   0007_people_reports_index    an index for reports.reported_user
--   0007_people_delete_files     delete_account() returns the files to delete
--   0007_people_contacts         contacts, and starting a chat with your people
--   0007_people_inbox_speed      my_chats works out who you are and who you blocked once per call

-- ---------------------------------------------------------------------------
-- Part 1: delete account (App Store guideline 5.1.1(v)).
--
-- Settings → Delete account calls delete_account(), one transaction:
--   * Friends' saved catch-ups and answers in chats this person wrote in are
--     deleted, so their words don't outlive them inside someone else's
--     summary. The next Catch me up reads the chat fresh.
--   * Deleting the auth user cascades to the profile, every membership (a
--     chat they were the last one in goes too, through apply_member_change),
--     every message they sent, their own briefs, join attempts and text usage.
--   * Chats they wrote in get their inbox line (last message, preview,
--     sender) recomputed from what's left, so no preview quotes them.
-- Their messages go with them instead of staying behind as "Deleted account":
-- what someone wrote is theirs, and a message with the name taken off still
-- says who wrote it in a group of friends. The others keep the chat.

create or replace function public.delete_account()
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  touched uuid[];
begin
  if me is null then raise exception 'Not signed in'; end if;

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
         (select m.created_at, left(m.body, 140), m.sender
            from public.messages m
           where m.chat_id = c.id
           order by m.created_at desc
           limit 1)
   where c.id = any (touched);
end;
$$;

revoke execute on function public.delete_account() from public, anon;
grant execute on function public.delete_account() to authenticated;

-- ---------------------------------------------------------------------------
-- Part 1b: delete_account() writes a chat's inbox line the way apply_message
-- does since 0006 part 2 (photo messages), so when a photo is what's left as
-- the last message the line reads "📷 Photo" (or "📷 " and its caption), not
-- an empty preview. Same function otherwise. Needs 0006 part 2
-- (messages.image_path).

create or replace function public.delete_account()
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  touched uuid[];
begin
  if me is null then raise exception 'Not signed in'; end if;

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
           where m.chat_id = c.id
           order by m.created_at desc
           limit 1)
   where c.id = any (touched);
end;
$$;

revoke execute on function public.delete_account() from public, anon;
grant execute on function public.delete_account() to authenticated;

-- ---------------------------------------------------------------------------
-- Part 2: block and report (App Store guideline 1.2).
--
-- Block is one way and silent. A blocked person's messages are hidden from
-- the blocker everywhere, by Row Level Security on messages: REST reads,
-- Realtime (which applies the select policy for each subscriber) and the
-- catch-up edge function (which reads as the caller), so Muse Spark never
-- reads them for the blocker either. The blocked person stays in the chat,
-- sees everything as before, and isn't told.
--   * my_chats leaves their messages out of unread counts. When the newest
--     message in a chat is theirs, the inbox line shows the newest one the
--     blocker can see, and the chat sorts by that.
--   * The read cursor is a time, so mark_read needs nothing new: the
--     catch-up window (after the cursor) and every count come from what RLS
--     lets through. Unblocking brings their messages back; the ones from
--     before your cursor count as read.
--   * Blocking or unblocking deletes the blocker's saved catch-ups that could
--     have read that person's messages, so a saved brief never shows what's
--     now hidden, or leaves out what's back.
--   * The messages policy now checks membership once per query (an array of
--     the caller's chats) instead of once per row, and blocks the same way.
--
-- Report: a message or a person, with a reason. Only the reporter can file
-- one and nobody reads them through the API; David reads them with SQL
-- (CLAUDE.md). The server copies the reported message and name into the
-- report, so it can still be reviewed if they're deleted later.

create table public.blocks (
  blocker    uuid not null references public.profiles(id) on delete cascade,
  blocked    uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker, blocked),
  constraint blocks_not_self check (blocker <> blocked)
);
create index blocks_blocked_idx on public.blocks (blocked);

alter table public.blocks enable row level security;
revoke all on public.blocks from public, anon, authenticated;
grant select on public.blocks to authenticated;

-- Your own blocks only. Writes go through block_person / unblock_person.
create policy blocks_select_own on public.blocks
  for select to authenticated
  using (blocker = (select auth.uid()));

-- The caller's chats and the people they've blocked, for policies. Each is
-- called as `(select f())`, so it runs once per query, not once per row.
create or replace function public.my_chat_ids()
returns uuid[]
language sql stable security definer
set search_path = public
as $$
  select coalesce(array_agg(chat_id), '{}') from public.chat_members where user_id = auth.uid();
$$;

create or replace function public.my_blocked_ids()
returns uuid[]
language sql stable security definer
set search_path = public
as $$
  select coalesce(array_agg(blocked), '{}') from public.blocks where blocker = auth.uid();
$$;

alter policy messages_select_member on public.messages
  using (chat_id = any ((select public.my_chat_ids())::uuid[])
         and sender <> all ((select public.my_blocked_ids())::uuid[]));

create or replace function public.block_person(p_user uuid)
returns void
language plpgsql security definer
set search_path = public
as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'Not signed in'; end if;
  if p_user is null or p_user = me then raise exception 'You can''t block yourself'; end if;
  insert into public.blocks (blocker, blocked) values (me, p_user)
  on conflict (blocker, blocked) do nothing;
end;
$$;

create or replace function public.unblock_person(p_user uuid)
returns void
language sql security definer
set search_path = public
as $$
  delete from public.blocks where blocker = auth.uid() and blocked = p_user;
$$;

-- Settings → Blocked people: everyone you've blocked, newest first, with the
-- name they have now (even if you no longer share a chat).
create or replace function public.my_blocks()
returns table (id uuid, display_name text, avatar_path text, blocked_at timestamptz)
language sql stable security definer
set search_path = public
as $$
  select p.id, p.display_name, p.avatar_path, b.created_at
    from public.blocks b
    join public.profiles p on p.id = b.blocked
   where b.blocker = auth.uid()
   order by b.created_at desc;
$$;

-- A saved catch-up is keyed on the read window, so after a block (or an
-- unblock) the same window would serve a brief made with the other set of
-- messages. Drop the blocker's briefs that could have read that person.
create or replace function public.apply_block_change()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  who uuid;
  whom uuid;
begin
  if tg_op = 'DELETE' then
    who := old.blocker; whom := old.blocked;
  else
    who := new.blocker; whom := new.blocked;
  end if;
  delete from public.ai_briefs b
   where b.user_id = who
     and exists (select 1 from public.messages m
                  where m.chat_id = b.chat_id and m.sender = whom and m.created_at <= b.until);
  return null;
end;
$$;

create trigger blocks_change
  after insert or delete on public.blocks
  for each row execute function public.apply_block_change();

-- The inbox, with blocks: unread counts leave blocked senders out, and a chat
-- whose newest message is from someone you blocked shows (and sorts by) the
-- newest one you can see. Same columns as before, so older apps keep working.
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
  with me as (select auth.uid() as id),
       blocked as (select public.my_blocked_ids() as ids)
  select c.id, c.name, c.invite_code, c.member_count, c.created_at,
         case when h.hidden then v.created_at else c.last_message_at end,
         case when h.hidden then v.preview else c.last_message_preview end,
         case when h.hidden then vp.display_name else p.display_name end,
         m.last_read_at,
         (select count(*)::int from public.messages x
           where x.chat_id = c.id and x.created_at > m.last_read_at
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
       where h.hidden and x.chat_id = c.id and x.sender <> all (blocked.ids)
       order by x.created_at desc
       limit 1) v on true
    left join public.profiles p on p.id = c.last_message_sender
    left join public.profiles vp on vp.id = v.sender
   order by coalesce(case when h.hidden then v.created_at else c.last_message_at end, c.created_at) desc;
$$;

create table public.reports (
  id            uuid primary key default gen_random_uuid(),
  reporter      uuid default auth.uid() references public.profiles(id) on delete set null,
  reported_user uuid references public.profiles(id) on delete set null,
  message_id    uuid,  -- no foreign key: the report outlives the message
  chat_id       uuid,  -- and the chat
  reason        text not null constraint reports_reason_check
                  check (reason in ('spam', 'harassment', 'hate', 'threats', 'sexual', 'other')),
  note          text constraint reports_note_check check (note is null or char_length(note) <= 500),
  reported_name text,  -- copied by the server when the report is filed
  message_body  text,
  message_image text,  -- the photo's storage path, if the message had one
  created_at    timestamptz not null default now(),
  emailed_at    timestamptz,  -- set by the report-alert edge function
  reviewed_at   timestamptz,  -- set by David once he's looked
  constraint reports_target_check check (message_id is not null or reported_user is not null)
);
create index reports_new_idx on public.reports (created_at desc) where reviewed_at is null;
create index reports_reporter_idx on public.reports (reporter, created_at desc);

alter table public.reports enable row level security;
revoke all on public.reports from public, anon, authenticated;
-- The client picks the id (so it can ask report-alert to email about it) and
-- says what's reported and why. The server fills in the rest.
grant insert (id, reported_user, message_id, reason, note) on public.reports to authenticated;

create policy reports_insert_own on public.reports
  for insert to authenticated
  with check (reporter = (select auth.uid()));
-- No select, update or delete policy: nobody reads reports through the API.

-- Fills in a report from what the reporter can see: the reported person and
-- copies of the message and name. Only messages in your own chats, never
-- your own, only people you share a chat with. 20 an hour; the same message
-- (or person) twice in a day keeps the first report and drops the second.
create or replace function public.fill_report()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  msg public.messages;
begin
  if me is null then raise exception 'Not signed in'; end if;
  new.reporter := me;
  new.created_at := now();
  new.emailed_at := null;
  new.reviewed_at := null;
  new.note := nullif(btrim(coalesce(new.note, '')), '');
  if new.message_id is not null then
    select * into msg from public.messages where id = new.message_id;
    if not found or not exists (select 1 from public.chat_members
                                 where chat_id = msg.chat_id and user_id = me) then
      raise exception 'You can only report messages in your chats';
    end if;
    if msg.sender = me then raise exception 'You can''t report your own message'; end if;
    new.reported_user := msg.sender;
    new.chat_id := msg.chat_id;
    new.message_body := msg.body;
    new.message_image := msg.image_path;
  else
    if new.reported_user is null or new.reported_user = me then
      raise exception 'Pick someone to report';
    end if;
    if not public.shares_chat_with(new.reported_user) then
      raise exception 'You can only report people in your chats';
    end if;
    new.chat_id := null;
    new.message_body := null;
    new.message_image := null;
  end if;
  new.reported_name := (select display_name from public.profiles where id = new.reported_user);
  if (select count(*) from public.reports
       where reporter = me and created_at > now() - interval '1 hour') >= 20 then
    raise exception 'That''s a lot of reports. Try again in a bit.';
  end if;
  if exists (select 1 from public.reports r
              where r.reporter = me and r.created_at > now() - interval '1 day'
                and ((new.message_id is not null and r.message_id = new.message_id)
                  or (new.message_id is null and r.message_id is null
                      and r.reported_user = new.reported_user))) then
    return null;
  end if;
  return new;
end;
$$;

create trigger reports_fill
  before insert on public.reports
  for each row execute function public.fill_report();

revoke execute on function public.my_chat_ids(), public.my_blocked_ids(), public.block_person(uuid),
  public.unblock_person(uuid), public.my_blocks() from public, anon;
grant execute on function public.my_chat_ids(), public.my_blocked_ids(), public.block_person(uuid),
  public.unblock_person(uuid), public.my_blocks() to authenticated;
revoke execute on function public.apply_block_change(), public.fill_report() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Part 2b: an index for reports.reported_user, so deleting an account (which
-- sets it to null on reports about them) doesn't scan the whole table.

create index reports_reported_user_idx on public.reports (reported_user);

-- ---------------------------------------------------------------------------
-- Part 3: delete_account() returns the files the person uploaded.
--
-- SQL can't delete Storage files, and once the rows are gone the person's
-- own permissions can't either (reading a chat photo needs membership). So
-- the delete-account edge function calls this as the person, then deletes
-- the files it returns with the service role, through the Storage API: rows
-- first, so a failed delete changes nothing; files after, server side. It
-- returns {"avatars": [paths], "chat-media": [paths]}: their avatar folder
-- and every chat photo (and thumbnail) they uploaded. Otherwise the same as
-- part 1b. A new return type, so it's dropped and made again (grants too).

drop function public.delete_account();

create function public.delete_account()
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
           where m.chat_id = c.id
           order by m.created_at desc
           limit 1)
   where c.id = any (touched);

  return files;
end;
$$;

revoke execute on function public.delete_account() from public, anon;
grant execute on function public.delete_account() to authenticated;

-- ---------------------------------------------------------------------------
-- Part 4: your people (contacts), and starting a chat with them.
--
-- A contact is someone you add from their profile, and only from a chat you
-- share: there's no lookup by email or phone, so nobody can find out who
-- uses Ketchup. Only you see your list. Starting a chat with your people
-- adds them straight in, except anyone who has blocked you (or you them):
-- they're left out quietly, so a block stays private. Blocking someone also
-- takes them out of your people.

create table public.contacts (
  owner      uuid not null references public.profiles(id) on delete cascade,
  contact    uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (owner, contact),
  constraint contacts_not_self check (owner <> contact)
);
create index contacts_contact_idx on public.contacts (contact);

alter table public.contacts enable row level security;
revoke all on public.contacts from public, anon, authenticated;
grant select on public.contacts to authenticated;

-- Your own list only. Writes go through add_contact / remove_contact.
create policy contacts_select_own on public.contacts
  for select to authenticated
  using (owner = (select auth.uid()));

create or replace function public.add_contact(p_user uuid)
returns void
language plpgsql security definer
set search_path = public
as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'Not signed in'; end if;
  if p_user is null or p_user = me then raise exception 'That''s you'; end if;
  if not public.shares_chat_with(p_user) then
    raise exception 'You can add people from your chats';
  end if;
  if (select count(*) from public.contacts where owner = me) >= 500 then
    raise exception 'That''s a lot of people already';
  end if;
  insert into public.contacts (owner, contact) values (me, p_user)
  on conflict (owner, contact) do nothing;
end;
$$;

create or replace function public.remove_contact(p_user uuid)
returns void
language sql security definer
set search_path = public
as $$
  delete from public.contacts where owner = auth.uid() and contact = p_user;
$$;

-- Your people by name, with the name and photo they have now and how many
-- chats you share.
create or replace function public.my_contacts()
returns table (id uuid, display_name text, avatar_path text, added_at timestamptz, shared_chats integer)
language sql stable security definer
set search_path = public
as $$
  select p.id, p.display_name, p.avatar_path, k.created_at,
         (select count(*)::int
            from public.chat_members a
            join public.chat_members b on b.chat_id = a.chat_id
           where a.user_id = auth.uid() and b.user_id = p.id)
    from public.contacts k
    join public.profiles p on p.id = k.contact
   where k.owner = auth.uid()
   order by lower(p.display_name), p.id;
$$;

-- A new chat with some of your people in it from the start. Only people in
-- your list, never anyone who has blocked you or whom you've blocked (left
-- out without a word), at most 63 others. Like create_chat otherwise.
create or replace function public.create_chat_with(p_name text, p_people uuid[])
returns public.chats
language plpgsql security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  c public.chats;
begin
  if me is null then raise exception 'Not signed in'; end if;
  if coalesce(array_length(p_people, 1), 0) > 63 then
    raise exception 'A chat holds up to 64 people';
  end if;
  select * into c from public.create_chat(p_name);
  insert into public.chat_members (chat_id, user_id, last_read_at)
  select c.id, k.contact, c.created_at - interval '1 millisecond'
    from public.contacts k
   where k.owner = me
     and k.contact = any (coalesce(p_people, '{}'))
     and not exists (select 1 from public.blocks b
                      where (b.blocker = k.contact and b.blocked = me)
                         or (b.blocker = me and b.blocked = k.contact))
  on conflict (chat_id, user_id) do nothing;
  select * into c from public.chats where id = c.id;
  return c;
end;
$$;

-- Blocking someone also takes them out of your people.
create or replace function public.block_person(p_user uuid)
returns void
language plpgsql security definer
set search_path = public
as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'Not signed in'; end if;
  if p_user is null or p_user = me then raise exception 'You can''t block yourself'; end if;
  insert into public.blocks (blocker, blocked) values (me, p_user)
  on conflict (blocker, blocked) do nothing;
  delete from public.contacts where owner = me and contact = p_user;
end;
$$;

revoke execute on function public.add_contact(uuid), public.remove_contact(uuid), public.my_contacts(),
  public.create_chat_with(text, uuid[]) from public, anon;
grant execute on function public.add_contact(uuid), public.remove_contact(uuid), public.my_contacts(),
  public.create_chat_with(text, uuid[]) to authenticated;

-- ---------------------------------------------------------------------------
-- Part 5: the inbox stays quick on a busy account.
--
-- Measured with supabase/tests/speed_check.sql (a rolled-back account with
-- a 20,000-message chat, 5,000 unread): my_chats() took about 65 ms, because
-- Postgres inlined both CTEs into the unread count, so my_blocked_ids() and
-- auth.uid() (a settings read and a JSON parse) ran once for every unread
-- message. `as materialized` runs each once per call: about 8.5 ms with only
-- `blocked` materialized, about 2 ms with both. Same columns and results as
-- part 2, checked side by side on the busy account, with and without a block.

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
           where x.chat_id = c.id and x.created_at > m.last_read_at
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
       where h.hidden and x.chat_id = c.id and x.sender <> all (blocked.ids)
       order by x.created_at desc
       limit 1) v on true
    left join public.profiles p on p.id = c.last_message_sender
    left join public.profiles vp on vp.id = v.sender
   order by coalesce(case when h.hidden then v.created_at else c.last_message_at end, c.created_at) desc;
$$;
