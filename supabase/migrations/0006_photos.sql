-- Photos (Nov 3, 2026). Applied live in parts, one per slice:
--   part 1, profile photos  (live migration 0006_photos_1_avatars)
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
