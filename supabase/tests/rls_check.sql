-- RLS check: runs as two fake members and an outsider inside one transaction
-- and rolls everything back. Run with the Supabase SQL editor (or MCP
-- execute_sql). Every line of the final select should say pass = true.
begin;

create temp table results (name text, pass boolean) on commit drop;
grant all on results to authenticated;

insert into auth.users (id, email, aud, role, instance_id)
values ('00000000-0000-0000-0000-0000000000a1', 'alice@test.ketchup', 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'),
       ('00000000-0000-0000-0000-0000000000b2', 'bob@test.ketchup',   'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'),
       ('00000000-0000-0000-0000-0000000000c3', 'eve@test.ketchup',   'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000');

insert into results select 'profiles created by trigger',
  (select count(*) from public.profiles where id in ('00000000-0000-0000-0000-0000000000a1',
    '00000000-0000-0000-0000-0000000000b2','00000000-0000-0000-0000-0000000000c3')) = 3;

-- Alice creates a chat and posts.
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
create temp table ctx as select * from public.create_chat('Friday crew');
insert into public.messages (chat_id, body) select id, 'hi from alice' from ctx;
insert into results select 'creator sees chat', (select count(*) from public.chats) = 1;
insert into results select 'creator is member', (select member_count from public.chats) = 1;

-- Bob joins with the code (lower case, spaced) and posts.
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b2","role":"authenticated"}', true);
insert into results select 'outsider cannot see chat before joining', (select count(*) from public.chats) = 0;
insert into results select 'join with messy code',
  (select j.id from ctx, lateral public.join_chat(lower(substr(ctx.invite_code,1,3)) || ' ' || substr(ctx.invite_code,4)) j) = (select id from ctx);
insert into results select 'joiner sees history', (select count(*) from public.messages) = 1;
insert into results select 'joiner sees alice profile', (select count(*) from public.profiles) = 2;
insert into results select 'new member: whole history unread', (select unread_count from public.my_chats()) = 1;
insert into public.messages (chat_id, body) select id, '  hi from bob  ' from ctx;
insert into results select 'replying marks earlier messages read', (select unread_count from public.my_chats()) = 0;
insert into results select 'body trimmed', exists (select 1 from public.messages where body = 'hi from bob');

-- Bob cannot post as Alice.
do $$ begin
  insert into public.messages (chat_id, body, sender)
  select id, 'spoof', '00000000-0000-0000-0000-0000000000a1' from ctx;
  insert into results values ('cannot spoof sender', false);
exception when others then insert into results values ('cannot spoof sender', true); end $$;

-- Eve: outsider.
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000c3","role":"authenticated"}', true);
insert into results select 'outsider sees no chats',    (select count(*) from public.chats) = 0;
insert into results select 'outsider sees no messages', (select count(*) from public.messages) = 0;
insert into results select 'outsider sees no members',  (select count(*) from public.chat_members) = 0;
insert into results select 'outsider sees only self',   (select count(*) from public.profiles) = 1;
do $$ begin
  insert into public.messages (chat_id, body) select id, 'let me in' from ctx;
  insert into results values ('outsider cannot post', false);
exception when others then insert into results values ('outsider cannot post', true); end $$;
do $$ begin
  insert into public.chat_members (chat_id, user_id) select id, auth.uid() from ctx;
  insert into results values ('outsider cannot self-add', false);
exception when others then insert into results values ('outsider cannot self-add', true); end $$;
do $$ begin
  update public.chats set name = 'pwned';
  insert into results values ('no direct chat updates', false);
exception when others then insert into results values ('no direct chat updates', true); end $$;
insert into results select 'wrong code returns empty row', (select id is null from public.join_chat('ZZZZZZ'));
insert into results values ('wrong code counted (not rolled back)', false);  -- checked below as postgres
do $$ begin
  perform * from public.ai_briefs;
  insert into results values ('ai_briefs readable but empty', true);
exception when others then insert into results values ('ai_briefs readable but empty', false); end $$;
-- catch-up-text's usage counts (0004): no client access at all.
do $$ begin
  perform * from public.text_brief_usage;
  insert into results values ('text usage closed to clients', false);
exception when others then insert into results values ('text usage closed to clients', true); end $$;
do $$ begin
  perform public.take_text_brief(auth.uid(), 'instagram', 'ask', 1, 100);
  insert into results values ('clients cannot spend the text cap', false);
exception when others then insert into results values ('clients cannot spend the text cap', true); end $$;

reset role;
update results set pass = (select count(*) = 1 from public.join_attempts
  where user_id = '00000000-0000-0000-0000-0000000000c3')
 where name = 'wrong code counted (not rolled back)';

-- The text cap, as the edge function calls it: 2 of 2 allowed (one per
-- source, so both count toward it), then a refusal that isn't counted.
grant all on results to service_role;
set local role service_role;
insert into results select 'text cap allows the 1st use',
  public.take_text_brief('00000000-0000-0000-0000-0000000000a1', 'instagram', 'catch_up', 120, 2);
insert into results select 'text cap allows the 2nd use (snapchat)',
  public.take_text_brief('00000000-0000-0000-0000-0000000000a1', 'snapchat', 'ask', 120, 2);
insert into results select 'text cap refuses the 3rd use',
  not public.take_text_brief('00000000-0000-0000-0000-0000000000a1', 'instagram', 'catch_up', 120, 2);
reset role;
insert into results select 'refused text use not counted',
  (select count(*) = 2 from public.text_brief_usage where user_id = '00000000-0000-0000-0000-0000000000a1');
do $$ begin
  insert into public.text_brief_usage (user_id, source, mode, message_count)
  values ('00000000-0000-0000-0000-0000000000a1', 'tiktok', 'ask', 1);
  insert into results values ('unknown text source refused', false);
exception when check_violation then insert into results values ('unknown text source refused', true); end $$;

-- Delete account (0007): Dan joins Friday crew, has the last word, then
-- deletes his account. His messages go, the inbox line falls back to Bob's,
-- and a catch-up Alice saved that read him goes too.
insert into auth.users (id, email, aud, role, instance_id)
values ('00000000-0000-0000-0000-0000000000d4', 'dan@test.ketchup', 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000');
grant all on results to anon;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000d4","role":"authenticated"}', true);
select public.join_chat(invite_code) from ctx;
insert into public.messages (chat_id, body) select id, 'hi from dan' from ctx;
reset role;
-- Every message here shares now(): put Bob's last before Dan's. Bob's is a
-- captioned photo (0006), so the line falls back to "📷 hi from bob".
update public.messages set created_at = now() - interval '2 minutes' where body = 'hi from alice';
update public.messages set created_at = now() - interval '1 minute',
       image_path = chat_id::text || '/00000000-0000-4000-8000-0000000000b2.jpg', image_width = 800, image_height = 600
 where body = 'hi from bob';
insert into public.ai_briefs (chat_id, user_id, kind, since, until, message_count, model, result)
select id, '00000000-0000-0000-0000-0000000000a1', 'catch_up', now() - interval '1 hour', now(), 3, 'test', '{}' from ctx;
set local role anon;
do $$ begin
  perform public.delete_account();
  insert into results values ('delete account closed to anon', false);
exception when insufficient_privilege then insert into results values ('delete account closed to anon', true); end $$;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000d4","role":"authenticated"}', true);
select public.delete_account();
reset role;
insert into results select 'deleted account: profile gone',
  not exists (select 1 from public.profiles where id = '00000000-0000-0000-0000-0000000000d4');
insert into results select 'deleted account: messages gone',
  not exists (select 1 from public.messages where sender = '00000000-0000-0000-0000-0000000000d4');
insert into results select 'deleted account: inbox line falls back',
  (select last_message_preview = '📷 hi from bob' and member_count = 2 from public.chats where id = (select id from ctx));
insert into results select 'deleted account: catch-ups that read them go',
  not exists (select 1 from public.ai_briefs where chat_id = (select id from ctx));

-- Profile photos (0006): your own folder only, a path into your own folder
-- only, nobody lists the bucket, 10 uploads an hour. storage.operation and
-- storage.allow_delete_query stand in for what the Storage API sets.
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
insert into storage.objects (bucket_id, name, owner_id)
values ('avatars', '00000000-0000-0000-0000-0000000000a1/11111111-1111-4111-8111-111111111111.jpg', '00000000-0000-0000-0000-0000000000a1');
insert into results select 'avatar upload into own folder', (select count(*) = 1 from storage.objects where bucket_id = 'avatars');
do $$ begin
  insert into storage.objects (bucket_id, name, owner_id)
  values ('avatars', '00000000-0000-0000-0000-0000000000b2/22222222-2222-4222-8222-222222222222.jpg', '00000000-0000-0000-0000-0000000000a1');
  insert into results values ('avatar upload into another folder refused', false);
exception when others then insert into results values ('avatar upload into another folder refused', true); end $$;
update public.profiles set avatar_path = '00000000-0000-0000-0000-0000000000a1/11111111-1111-4111-8111-111111111111.jpg'
 where id = auth.uid();
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b2","role":"authenticated"}', true);
insert into results select 'chat-mate sees avatar_path',
  (select avatar_path is not null from public.profiles where id = '00000000-0000-0000-0000-0000000000a1');
do $$ begin
  update public.profiles set avatar_path = '00000000-0000-0000-0000-0000000000a1/11111111-1111-4111-8111-111111111111.jpg'
   where id = auth.uid();
  insert into results values ('avatar_path only into own folder', false);
exception when check_violation then insert into results values ('avatar_path only into own folder', true); end $$;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000c3","role":"authenticated"}', true);
select set_config('storage.operation', 'object.list', true);
insert into results select 'avatars bucket not listable', (select count(*) = 0 from storage.objects where bucket_id = 'avatars');
select set_config('storage.allow_delete_query', 'true', true);
with d as (delete from storage.objects where bucket_id = 'avatars' returning 1)
insert into results select 'cannot delete someone else''s avatar', (select count(*) = 0 from d);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
with d as (delete from storage.objects where bucket_id = 'avatars' returning 1)
insert into results select 'owner deletes own avatar', (select count(*) = 1 from d);
do $$ declare uploaded int := 0; begin
  for i in 1..11 loop
    begin
      insert into storage.objects (bucket_id, name, owner_id)
      values ('avatars', '00000000-0000-0000-0000-0000000000a1/' || gen_random_uuid() || '.jpg', '00000000-0000-0000-0000-0000000000a1');
      uploaded := uploaded + 1;
    exception when others then exit;
    end;
  end loop;
  insert into results values ('avatar uploads capped at 10 an hour', uploaded = 10);
end $$;

-- Photos in chats (0006 part 2): members read and upload into their chat's
-- folder, a photo message needs its photo uploaded first and in its own
-- chat, and only the uploader deletes a file. Alice is still signed in.
create temp table ctx2 as select * from public.create_chat('Other chat');
insert into storage.objects (bucket_id, name, owner_id)
select 'chat-media', id || '/33333333-3333-4333-8333-333333333333.jpg', '00000000-0000-0000-0000-0000000000a1' from ctx
union all
select 'chat-media', id || '/33333333-3333-4333-8333-333333333333_small.jpg', '00000000-0000-0000-0000-0000000000a1' from ctx
union all
select 'chat-media', id || '/44444444-4444-4444-8444-444444444444.jpg', '00000000-0000-0000-0000-0000000000a1' from ctx2;
insert into public.messages (chat_id, body, image_path, image_width, image_height)
select id, '', id || '/33333333-3333-4333-8333-333333333333.jpg', 2048, 1536 from ctx;
insert into results select 'photo without words sends, inbox says Photo',
  (select last_message_preview = '📷 Photo' from public.chats where id = (select id from ctx));
do $$ begin
  insert into public.messages (chat_id, body, image_path, image_width, image_height)
  select id, '', id || '/55555555-5555-4555-8555-555555555555.jpg', 10, 10 from ctx;
  insert into results values ('photo must be uploaded first', false);
exception when others then insert into results values ('photo must be uploaded first', true); end $$;
do $$ begin
  insert into public.messages (chat_id, body, image_path, image_width, image_height)
  select ctx.id, 'look', ctx2.id || '/44444444-4444-4444-8444-444444444444.jpg', 10, 10 from ctx, ctx2;
  insert into results values ('photo from another chat refused', false);
exception when check_violation then insert into results values ('photo from another chat refused', true); end $$;
do $$ begin
  insert into public.messages (chat_id, body, image_width, image_height) select id, 'hi', 10, 10 from ctx;
  insert into results values ('photo size without a photo refused', false);
exception when check_violation then insert into results values ('photo size without a photo refused', true); end $$;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b2","role":"authenticated"}', true);
insert into results select 'member reads chat photos',
  (select count(*) = 2 from storage.objects where bucket_id = 'chat-media');
with d as (delete from storage.objects where bucket_id = 'chat-media' returning 1)
insert into results select 'member cannot delete others'' photos', (select count(*) = 0 from d);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000c3","role":"authenticated"}', true);
insert into results select 'outsider cannot read chat photos',
  (select count(*) = 0 from storage.objects where bucket_id = 'chat-media');
do $$ begin
  insert into storage.objects (bucket_id, name, owner_id)
  select 'chat-media', id || '/66666666-6666-4666-8666-666666666666.jpg', '00000000-0000-0000-0000-0000000000c3' from ctx;
  insert into results values ('outsider cannot upload into a chat', false);
exception when others then insert into results values ('outsider cannot upload into a chat', true); end $$;
reset role;

select * from results;
rollback;
