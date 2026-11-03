-- Speed check: times the app's hot paths with EXPLAIN ANALYZE (median of 7
-- runs) on today's data, then again on a busy account built inside this
-- transaction, and rolls everything back. Run it with execute_sql after a
-- schema change and compare with the numbers in 0008_speed_indexes.sql.
-- Paths 1 to 4 run as David under RLS, as the app reads them; 5 to 7 run as
-- the server does (catch-up's service role, the send trigger).
--
-- The busy account: a 20,000-message chat with 5,000 unread, 20 more chats
-- of 300 messages, David the sender of a quarter of it, and 3,000 saved
-- briefs. Triggers are skipped for the bulk load (session_replication_role),
-- so the real chats' rows are never touched.
begin;
create temp table timings(step text, phase text, ms numeric, uses text) on commit drop;

create function pg_temp.measure(p_step text, p_phase text, p_sql text, p_user uuid) returns void
language plpgsql as $f$
declare plan json; times numeric[] := '{}'; uses text; i int;
begin
  for i in 1..7 loop
    if p_user is not null then
      perform set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
      perform set_config('role', 'authenticated', true);
    end if;
    execute 'explain (analyze, format json) ' || p_sql into plan;
    perform set_config('role', 'postgres', true);
    times := times || (plan->0->>'Execution Time')::numeric;
  end loop;
  select string_agg(distinct x #>> '{}', ', ') into uses from jsonb_path_query(plan::jsonb, '$.**."Index Name"') x;
  insert into timings values (p_step, p_phase,
    (select percentile_cont(0.5) within group (order by t) from unnest(times) t), coalesce(uses, 'no index'));
end $f$;

create function pg_temp.measure_all(p_phase text, david uuid, chat uuid, cursor_at timestamptz,
                                    since_at timestamptz, until_at timestamptz) returns void
language plpgsql as $f$
begin
  perform pg_temp.measure('1 open chat: newest 327', p_phase, format(
    'select id, chat_id, sender, body, created_at, image_path, image_width, image_height from public.messages where chat_id = %L order by created_at desc limit 327', chat), david);
  perform pg_temp.measure('2 open chat: members', p_phase, format(
    'select m.user_id, m.joined_at, m.last_read_at, p.display_name, p.avatar_path from public.chat_members m left join public.profiles p on p.id = m.user_id where m.chat_id = %L order by m.joined_at', chat), david);
  perform pg_temp.measure('3 inbox: my_chats()', p_phase, 'select * from public.my_chats()', david);
  perform pg_temp.measure('4 catch-up: unread read', p_phase, format(
    'select id, sender, body, created_at, image_path from public.messages where chat_id = %L and created_at > %L order by created_at desc limit 600', chat, cursor_at), david);
  perform pg_temp.measure('5 catch-up: saved-brief lookup', p_phase, format(
    'select id, result, model from public.ai_briefs where user_id = %L and chat_id = %L and kind = %L and since = %L and until = %L and question is null and model <> %L order by created_at desc limit 1',
    david, chat, 'catch_up', since_at, until_at, 'pending'), null);
  perform pg_temp.measure('6 catch-up: hourly cap count', p_phase, format(
    'select count(*) from public.ai_briefs where user_id = %L and created_at >= now() - interval %L', david, '1 hour'), null);
  perform pg_temp.measure('7 every send: rate check', p_phase, format(
    'select count(*) from public.messages where sender = %L and created_at > now() - interval %L', david, '10 seconds'), null);
end $f$;

do $$
declare
  breck uuid; david uuid; friends uuid[]; cursor_at timestamptz;
  big uuid := gen_random_uuid(); small uuid; i int;
  alphabet text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  code text;
begin
  select id into breck from public.chats where name like 'Breck%' limit 1;
  select m.user_id into david from public.chat_members m join public.profiles p on p.id = m.user_id
   where m.chat_id = breck and p.display_name = 'David' limit 1;
  if david is null then
    select user_id into david from public.chat_members where chat_id = breck order by joined_at desc limit 1;
  end if;
  select array_agg(user_id) into friends from public.chat_members where chat_id = breck and user_id <> david;
  select last_read_at into cursor_at from public.chat_members where chat_id = breck and user_id = david;

  perform pg_temp.measure_all('today', david, breck, cursor_at, cursor_at, now());

  set local session_replication_role = replica;
  code := (select string_agg(substr(alphabet, 1 + floor(random() * 32)::int, 1), '') from generate_series(1, 6));
  insert into public.chats (id, name, invite_code, created_by, created_at, member_count, last_message_at)
  values (big, 'Scale test', code, david, now() - interval '40 days', 6, now());
  insert into public.chat_members (chat_id, user_id, joined_at, last_read_at)
  select big, u, now() - interval '40 days', now() - interval '40 days' from unnest(friends || david) u;
  update public.chat_members set last_read_at = now() - interval '30 days' + (15000 * interval '2 minutes')
   where chat_id = big and user_id = david;
  insert into public.messages (chat_id, sender, body, created_at)
  select big, case when g % 4 = 0 then david else friends[1 + g % array_length(friends, 1)] end,
         'scale message ' || g, now() - interval '30 days' + (g * interval '2 minutes')
    from generate_series(1, 20000) g;
  for i in 1..20 loop
    small := gen_random_uuid();
    code := (select string_agg(substr(alphabet, 1 + floor(random() * 32)::int, 1), '') from generate_series(1, 6));
    insert into public.chats (id, name, invite_code, created_by, created_at, member_count, last_message_at)
    values (small, 'Scale ' || i, code, david, now() - interval '20 days', 3, now() - (i * interval '1 hour'));
    insert into public.chat_members (chat_id, user_id, joined_at, last_read_at)
    select small, u, now() - interval '20 days', now() - interval '2 days' from unnest(friends[1:2] || david) u;
    insert into public.messages (chat_id, sender, body, created_at)
    select small, case when g % 3 = 0 then david else friends[1 + g % 2] end,
           'small ' || g, now() - interval '20 days' + (g * interval '1 hour') / 16
      from generate_series(1, 300) g;
  end loop;
  insert into public.ai_briefs (chat_id, user_id, kind, question, since, until, message_count, model, result, created_at)
  select breck, david, case when g % 3 = 0 then 'ask' else 'catch_up' end,
         case when g % 3 = 0 then 'question ' || g end,
         now() - interval '61 days' + (g * interval '28 minutes'),
         now() - interval '61 days' + (g * interval '28 minutes') + interval '1 hour',
         100, 'muse-spark-1.3', '{}', now() - interval '61 days' + (g * interval '29 minutes')
    from generate_series(1, 3000) g;
  set local session_replication_role = origin;
  analyze public.messages; analyze public.chats; analyze public.chat_members; analyze public.ai_briefs;

  perform pg_temp.measure_all('busy account', david, big, now() - interval '30 days' + (15000 * interval '2 minutes'),
    now() - interval '61 days' + (1501 * interval '28 minutes'), now() - interval '61 days' + (1501 * interval '28 minutes') + interval '1 hour');
end $$;

select step,
       max(round(ms, 3)) filter (where phase = 'today') as today_ms,
       max(round(ms, 3)) filter (where phase = 'busy account') as busy_ms,
       max(uses) filter (where phase = 'busy account') as busy_uses
  from timings group by step order by step;
rollback;
