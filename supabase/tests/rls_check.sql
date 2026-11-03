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

-- The text cap, as the edge function calls it: 2 of 2 allowed, then a
-- refusal that isn't counted.
grant all on results to service_role;
set local role service_role;
insert into results select 'text cap allows the 1st use',
  public.take_text_brief('00000000-0000-0000-0000-0000000000a1', 'instagram', 'catch_up', 120, 2);
insert into results select 'text cap allows the 2nd use',
  public.take_text_brief('00000000-0000-0000-0000-0000000000a1', 'instagram', 'ask', 120, 2);
insert into results select 'text cap refuses the 3rd use',
  not public.take_text_brief('00000000-0000-0000-0000-0000000000a1', 'instagram', 'catch_up', 120, 2);
reset role;
insert into results select 'refused text use not counted',
  (select count(*) = 2 from public.text_brief_usage where user_id = '00000000-0000-0000-0000-0000000000a1');

select * from results;
rollback;
