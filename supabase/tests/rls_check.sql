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

-- Block (0007): Bob blocks Alice. Her messages leave his reads, his unread
-- count and his inbox line, and his saved catch-up that read her goes. Alice
-- still sees Bob, and nobody can see who blocked them. Then he unblocks.
update public.chat_members set last_read_at = now() - interval '1 hour'
 where user_id = '00000000-0000-0000-0000-0000000000b2';
insert into public.ai_briefs (chat_id, user_id, kind, since, until, message_count, model, result)
select id, '00000000-0000-0000-0000-0000000000b2', 'catch_up', now() - interval '1 hour', now(), 2, 'test', '{}' from ctx;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
insert into public.messages (chat_id, body) select id, 'alice again' from ctx;
reset role;
-- Earlier than the messages below, so the delete-account checks keep Bob's as the last.
update public.messages set created_at = now() - interval '3 minutes' where body = 'alice again';
create temp table alice_msg as select id from public.messages where body = 'alice again';
grant select on alice_msg to authenticated;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b2","role":"authenticated"}', true);
insert into results select 'before block: her 2 messages unread', (select unread_count from public.my_chats()) = 2;
select public.block_person('00000000-0000-0000-0000-0000000000a1');
insert into results select 'blocked: her messages hidden',
  (select count(*) from public.messages where sender = '00000000-0000-0000-0000-0000000000a1') = 0;
insert into results select 'blocked: his own still there',
  (select count(*) from public.messages where sender = '00000000-0000-0000-0000-0000000000b2') = 1;
insert into results select 'blocked: unread leaves her out', (select unread_count from public.my_chats()) = 0;
insert into results select 'blocked: inbox line skips her',
  (select last_message_preview = 'hi from bob' and last_message_sender_name = 'bob' from public.my_chats());
insert into results select 'blocked: listed in my_blocks',
  (select count(*) from public.my_blocks() where id = '00000000-0000-0000-0000-0000000000a1') = 1;
do $$ begin
  perform public.block_person(auth.uid());
  insert into results values ('cannot block yourself', false);
exception when others then insert into results values ('cannot block yourself', true); end $$;
do $$ begin
  insert into public.blocks (blocker, blocked) values (auth.uid(), '00000000-0000-0000-0000-0000000000c3');
  insert into results values ('blocks written only through the RPCs', false);
exception when insufficient_privilege then insert into results values ('blocks written only through the RPCs', true); end $$;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
insert into results select 'blocked person still sees the blocker',
  (select count(*) from public.messages where sender = '00000000-0000-0000-0000-0000000000b2') = 1;
insert into results select 'nobody sees who blocked them', (select count(*) from public.blocks) = 0;
reset role;
insert into results select 'block drops saved catch-ups that read her',
  not exists (select 1 from public.ai_briefs where user_id = '00000000-0000-0000-0000-0000000000b2');
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b2","role":"authenticated"}', true);
select public.unblock_person('00000000-0000-0000-0000-0000000000a1');
insert into results select 'unblocked: her messages are back',
  (select count(*) from public.messages where sender = '00000000-0000-0000-0000-0000000000a1') = 2;

-- Report (0007): Bob reports Alice's message (twice: the second is dropped)
-- and Alice herself. Nobody can read reports back, report themselves or set
-- the reporter, and an outsider can't report into a chat they aren't in.
insert into public.reports (message_id, reason) select id, 'spam' from alice_msg;
insert into public.reports (message_id, reason) select id, 'harassment' from alice_msg;
insert into public.reports (reported_user, reason, note) values ('00000000-0000-0000-0000-0000000000a1', 'other', '  rude  ');
do $$ begin
  perform * from public.reports;
  insert into results values ('reports unreadable', false);
exception when insufficient_privilege then insert into results values ('reports unreadable', true); end $$;
do $$ begin
  insert into public.reports (message_id, reason) select id, 'spam' from public.messages where body = 'hi from bob';
  insert into results values ('cannot report own message', false);
exception when others then insert into results values ('cannot report own message', true); end $$;
do $$ begin
  insert into public.reports (reporter, reported_user, reason)
  values ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000c3', 'spam');
  insert into results values ('cannot set the reporter', false);
exception when insufficient_privilege then insert into results values ('cannot set the reporter', true); end $$;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000c3","role":"authenticated"}', true);
do $$ begin
  insert into public.reports (message_id, reason) select id, 'spam' from alice_msg;
  insert into results values ('outsider cannot report a message', false);
exception when others then insert into results values ('outsider cannot report a message', true); end $$;
do $$ begin
  insert into public.reports (reported_user, reason) values ('00000000-0000-0000-0000-0000000000a1', 'spam');
  insert into results values ('outsider cannot report a stranger', false);
exception when others then insert into results values ('outsider cannot report a stranger', true); end $$;
reset role;
insert into results select 'report filed with copies',
  (select count(*) = 1 from public.reports
    where reporter = '00000000-0000-0000-0000-0000000000b2' and message_id = (select id from alice_msg)
      and reported_user = '00000000-0000-0000-0000-0000000000a1' and reported_name = 'alice'
      and message_body = 'alice again' and reason = 'spam' and chat_id = (select id from ctx));
insert into results select 'person report trims the note',
  (select note = 'rude' from public.reports
    where reporter = '00000000-0000-0000-0000-0000000000b2' and message_id is null);
insert into results select 'nothing stored for the outsider',
  not exists (select 1 from public.reports where reporter = '00000000-0000-0000-0000-0000000000c3');

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

select * from results;
rollback;
