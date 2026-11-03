-- Photos (Nov 3, 2026). Applied live in parts, one per slice:
--   part 1, profile photos  (live migration 0006_photos_1_avatars)
--   part 2, photos in chats (live migration 0006_photos_2_chat_media)
--
-- ---------------------------------------------------------------------------
-- Part 1: profile photos.
--
-- profiles.avatar_path points at the member's photo in the avatars bucket,
-- "<their uid>/<uuid>.jpg": a 512 px square JPEG the app crops and uploads.
-- Every upload gets a new name, so a path never changes what it shows and
-- the app caches each photo for good.
--   * The bucket is public: the app loads a photo from its public URL with
--     no token. Nobody can list it, though: the only select policy covers
--     your own folder, so other people's files can't be enumerated.
--   * You can only upload into, and delete from, your own "<uid>/" folder,
--     at most 10 uploads an hour. JPEG only, up to 1 MB (the app's are 70 to
--     150 KB); the Storage API enforces both.
--   * avatar_path can only point into your own folder (a check constraint),
--     so nobody can wear someone else's face.
--   * A replaced photo is deleted by the app, through the Storage API.
--     Deleting storage.objects rows with SQL would orphan the file.

alter table public.profiles
  add column avatar_path text
    constraint profiles_avatar_path_check
    check (avatar_path ~ ('^' || id::text || '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.jpg$'));

grant update (avatar_path) on public.profiles to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', true, 1048576, array['image/jpeg']);

-- Uploads in the last hour, so a bucket can't be filled from one account.
-- Definer: it counts the caller's files, which their own policies may hide.
create or replace function public.storage_uploads_ok(p_bucket text, p_per_hour integer)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select count(*) < p_per_hour
    from storage.objects
   where bucket_id = p_bucket
     and owner_id = (select auth.uid())::text
     and created_at > now() - interval '1 hour';
$$;

revoke execute on function public.storage_uploads_ok(text, integer) from public, anon;
grant execute on function public.storage_uploads_ok(text, integer) to authenticated;

create policy avatars_insert_own on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}\.jpg$'
    and public.storage_uploads_ok('avatars', 10)
  );

-- Your own folder only. The Storage API reads the row before it deletes it.
create policy avatars_select_own on storage.objects
  for select to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy avatars_delete_own on storage.objects
  for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);

-- ---------------------------------------------------------------------------
-- Part 2: photos in chats.
--
-- A photo message carries image_path, "<chat_id>/<uuid>.jpg" in the private
-- chat-media bucket (the photo, at most 2048 px), with "<uuid>_small.jpg"
-- next to it (768 px, for the thread and for Muse Spark), and the photo's
-- size in pixels, so the app can lay the bubble out before it loads. The
-- body is the caption, and may be empty when there's a photo.
--   * Only members of a chat can read its photos (the bucket is private;
--     the app asks for signed URLs) or upload into its folder, at most 200
--     files an hour. JPEG only, up to 5 MB.
--   * You can delete only files you uploaded (the app cleans up a send that
--     never made it).
--   * A message can only point at a photo already in its own chat's folder.
--   * The inbox shows a photo as "📷 Photo", or "📷 " and the caption.
-- Additive for the app already out there: it reads the columns it knew.

alter table public.messages
  add column image_path   text,
  add column image_width  integer,
  add column image_height integer;

alter table public.messages
  add constraint messages_image_check check (
    (image_path is null and image_width is null and image_height is null)
    -- coalesce: a NULL anywhere fails, where a bare NULL would pass a check.
    or coalesce(image_path ~ ('^' || chat_id::text || '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.jpg$')
                and image_width between 1 and 10000 and image_height between 1 and 10000, false));

alter table public.messages drop constraint messages_body_check;
alter table public.messages add constraint messages_body_check
  check (char_length(body) <= 2000 and (char_length(body) >= 1 or image_path is not null));

grant insert (image_path, image_width, image_height) on public.messages to authenticated;

-- 0001's hygiene, plus: a photo may go without words, and must be uploaded.
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
  if auth.uid() is not null
     and (select count(*) from public.messages
           where sender = new.sender and created_at > now() - interval '10 seconds') >= 20 then
    raise exception 'Sending too fast';
  end if;
  return new;
end;
$$;

-- 0001's summary line, with photos.
create or replace function public.apply_message()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
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

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('chat-media', 'chat-media', false, 5242880, array['image/jpeg']);

-- The chat a chat-media file belongs to: its folder, when that's a uuid.
create or replace function public.media_chat(p_name text)
returns uuid
language sql immutable
set search_path = ''
as $$
  select case when p_name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/'
              then left(p_name, 36)::uuid end;
$$;

create policy chat_media_select_member on storage.objects
  for select to authenticated
  using (bucket_id = 'chat-media' and public.is_chat_member(public.media_chat(name)));

create policy chat_media_insert_member on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'chat-media'
    and name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}(_small)?\.jpg$'
    and public.is_chat_member(public.media_chat(name))
    and public.storage_uploads_ok('chat-media', 200)
  );

create policy chat_media_delete_own on storage.objects
  for delete to authenticated
  using (bucket_id = 'chat-media' and owner_id = (select auth.uid())::text);
