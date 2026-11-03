-- Ketchup schema, part 10: plans, and how much Muse Spark reads for you a day.
--
-- Every Muse Spark call costs money, so each person gets a daily allowance of
-- messages Muse Spark reads for them: Free 150, Plus 400, Pro 1,000. Free
-- catch-ups go to Meta's contributor model, which Meta may train on; Plus and
-- Pro go to the regular, private Muse Spark. Pro also gets voice summaries.
-- Plus and Pro are Apple auto-renewable subscriptions (StoreKit 2).
--
-- plans: one row per person who has bought (or been given) a plan. No row,
--   or a row past its expires_at, means Free. Only the verify-purchase edge
--   function writes it (service role, through apply_purchase), after it has
--   checked Apple's signature on the transaction. People read their own row
--   and nothing else; nobody can write it from the app.
-- plan_usage: the messages Muse Spark read for each person each day. The day
--   is Denver's calendar day, so it turns over at midnight Mountain time
--   whatever zone the phone is in (a phone can't move the day to get a fresh
--   allowance). Only catch-up and catch-up-text write it (service role,
--   through take_plan_usage and give_back_plan_usage); a cached or shared
--   brief costs nothing, so it never gets here. No client access at all;
--   my_plan() reports it.
--
-- To give someone a plan by hand (the demo account, a tester), in the SQL editor:
--   insert into public.plans (user_id, plan, source, expires_at)
--   values ('<user id>', 'pro', 'manual', now() + interval '30 days')
--   on conflict (user_id) do update set plan = excluded.plan, source = excluded.source,
--     expires_at = excluded.expires_at, updated_at = now();

create table public.plans (
  user_id                 uuid primary key references public.profiles(id) on delete cascade,
  plan                    text not null constraint plans_plan_check check (plan in ('free', 'plus', 'pro')),
  -- app_store: a Production transaction Apple signed. sandbox: Apple's
  -- sandbox (TestFlight, App Review, sandbox testers). xcode-test: Xcode's
  -- local StoreKit test, which Apple doesn't sign, accepted only while the
  -- STOREKIT_XCODE_TEST secret is on. manual: given by hand in SQL.
  source                  text not null constraint plans_source_check
                            check (source in ('app_store', 'sandbox', 'xcode-test', 'manual')),
  product_id              text,
  original_transaction_id text,
  transaction_id          text,
  expires_at              timestamptz,
  updated_at              timestamptz not null default now(),
  -- Only a plan given by hand may run without an end.
  constraint plans_expiry_check check (source = 'manual' or expires_at is not null),
  -- An Xcode test purchase can't be checked with Apple, so it lasts a day at most.
  constraint plans_xcode_test_check check (source <> 'xcode-test' or expires_at <= updated_at + interval '24 hours')
);

-- One App Store subscription unlocks one Ketchup account. (Xcode's local
-- test numbers its transactions 0, 1, 2 on every simulator, so not those.)
create unique index plans_original_transaction_idx on public.plans (original_transaction_id)
  where original_transaction_id is not null and source in ('app_store', 'sandbox');

alter table public.plans enable row level security;
revoke all on public.plans from public, anon, authenticated;
grant select on public.plans to authenticated;

create policy plans_select_own on public.plans
  for select to authenticated
  using (user_id = (select auth.uid()));

create table public.plan_usage (
  user_id    uuid not null references public.profiles(id) on delete cascade,
  day        date not null,
  messages   integer not null default 0 constraint plan_usage_messages_check check (messages >= 0),
  calls      integer not null default 0 constraint plan_usage_calls_check check (calls >= 0),
  updated_at timestamptz not null default now(),
  primary key (user_id, day)
);

alter table public.plan_usage enable row level security;
revoke all on public.plan_usage from public, anon, authenticated;

-- Messages Muse Spark reads per day, by plan. The app's plan cards
-- (ios/Ketchup/Plans/PlanModels.swift) say the same numbers.
create or replace function public.plan_limit(p_plan text)
returns integer
language sql immutable
set search_path = public
as $$
  select case p_plan when 'pro' then 1000 when 'plus' then 400 else 150 end;
$$;

-- The day plan_usage counts in: Denver's calendar day.
create or replace function public.plan_day(p_at timestamptz)
returns date
language sql immutable
set search_path = public
as $$
  select (p_at at time zone 'America/Denver')::date;
$$;

-- When that day's allowance comes back: the next midnight in Denver.
create or replace function public.plan_resets_at(p_day date)
returns timestamptz
language sql immutable
set search_path = public
as $$
  select (p_day + 1)::timestamp at time zone 'America/Denver';
$$;

-- Someone's plan right now: their row's plan until it expires, then free.
create or replace function public.effective_plan(p_user uuid)
returns text
language sql stable security definer
set search_path = public
as $$
  select coalesce((select plan from public.plans
                    where user_id = p_user and (expires_at is null or expires_at > now())), 'free');
$$;

revoke execute on function public.effective_plan(uuid) from public, anon, authenticated;
grant execute on function public.effective_plan(uuid) to service_role;

-- Checks today's allowance and spends it in one step, before a Muse Spark
-- call. Refused (allowed = false) when what's used plus this read would go
-- over, and then nothing is counted. The advisory lock makes two requests at
-- once from one person take turns, so they can't both squeeze in under the
-- limit. Returns {allowed, plan, used, limit, day, resets_at}.
create or replace function public.take_plan_usage(p_user uuid, p_messages integer)
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  v_day   date := public.plan_day(now());
  v_plan  text;
  v_limit integer;
  v_used  integer;
begin
  if p_user is null or p_messages is null or p_messages < 1 then
    raise exception 'take_plan_usage needs a person and at least one message';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('take_plan_usage:' || p_user::text, 0));
  v_plan := public.effective_plan(p_user);
  v_limit := public.plan_limit(v_plan);
  select coalesce(sum(u.messages), 0) into v_used
    from public.plan_usage u where u.user_id = p_user and u.day = v_day;
  if v_used + p_messages > v_limit then
    return jsonb_build_object('allowed', false, 'plan', v_plan, 'used', v_used, 'limit', v_limit,
                              'day', v_day, 'resets_at', public.plan_resets_at(v_day));
  end if;
  insert into public.plan_usage as u (user_id, day, messages, calls)
  values (p_user, v_day, p_messages, 1)
  on conflict (user_id, day) do update
    set messages = u.messages + excluded.messages,
        calls = u.calls + 1,
        updated_at = now();
  return jsonb_build_object('allowed', true, 'plan', v_plan, 'used', v_used + p_messages, 'limit', v_limit,
                            'day', v_day, 'resets_at', public.plan_resets_at(v_day));
end;
$$;

revoke execute on function public.take_plan_usage(uuid, integer) from public, anon, authenticated;
grant execute on function public.take_plan_usage(uuid, integer) to service_role;

-- A Muse Spark call that failed gives its messages back, to the day it took
-- them from (a call can straddle midnight).
create or replace function public.give_back_plan_usage(p_user uuid, p_day date, p_messages integer)
returns void
language sql security definer
set search_path = public
as $$
  update public.plan_usage
     set messages = greatest(0, messages - greatest(0, p_messages)),
         calls = greatest(0, calls - 1),
         updated_at = now()
   where user_id = p_user and day = p_day;
$$;

revoke execute on function public.give_back_plan_usage(uuid, date, integer) from public, anon, authenticated;
grant execute on function public.give_back_plan_usage(uuid, date, integer) to service_role;

-- Records a purchase verify-purchase has checked. Returns what happened:
--   'applied'  the plan is now this purchase's;
--   'stale'    an older transaction (a renewal that came late, the plan
--              before an upgrade, a plan given by hand that's better), so
--              nothing changed;
--   'taken'    this App Store subscription already unlocks another account;
--   'revoked'  Apple refunded or revoked it, so the plan it gave ends now.
-- An Xcode test purchase lasts at most 24 hours, whatever its expiry says.
create or replace function public.apply_purchase(
  p_user uuid, p_plan text, p_source text, p_product text, p_original_tx text, p_tx text,
  p_expires timestamptz, p_revoked_at timestamptz default null)
returns text
language plpgsql security definer
set search_path = public
as $$
declare
  v_current public.plans%rowtype;
  v_has     boolean;
  v_expires timestamptz := p_expires;
  v_rank    integer := case p_plan when 'pro' then 2 when 'plus' then 1 else 0 end;
begin
  if p_user is null or p_plan not in ('plus', 'pro') or p_source not in ('app_store', 'sandbox', 'xcode-test')
     or p_original_tx is null or p_expires is null then
    raise exception 'apply_purchase: incomplete purchase';
  end if;
  -- The subscription first, then the person, always in that order.
  perform pg_advisory_xact_lock(hashtextextended('apply_purchase:' || p_original_tx, 0));
  perform pg_advisory_xact_lock(hashtextextended('apply_purchase:' || p_user::text, 0));

  select * into v_current from public.plans where user_id = p_user for update;
  v_has := found;

  if p_revoked_at is not null then
    update public.plans set expires_at = least(expires_at, p_revoked_at), updated_at = now()
     where user_id = p_user and original_transaction_id = p_original_tx;
    return 'revoked';
  end if;

  if p_source in ('app_store', 'sandbox') and exists (
       select 1 from public.plans
        where original_transaction_id = p_original_tx and source in ('app_store', 'sandbox')
          and user_id <> p_user) then
    return 'taken';
  end if;

  if p_source = 'xcode-test' then
    v_expires := least(v_expires, now() + interval '24 hours');
  end if;

  if v_has and (v_current.expires_at is null or v_current.expires_at > now())
     and (v_current.expires_at is null or v_current.expires_at >= v_expires)
     and (case v_current.plan when 'pro' then 2 when 'plus' then 1 else 0 end) >= v_rank then
    return 'stale';
  end if;

  insert into public.plans (user_id, plan, source, product_id, original_transaction_id, transaction_id,
                            expires_at, updated_at)
  values (p_user, p_plan, p_source, p_product, p_original_tx, p_tx, v_expires, now())
  on conflict (user_id) do update
    set plan = excluded.plan, source = excluded.source, product_id = excluded.product_id,
        original_transaction_id = excluded.original_transaction_id, transaction_id = excluded.transaction_id,
        expires_at = excluded.expires_at, updated_at = excluded.updated_at;
  return 'applied';
end;
$$;

revoke execute on function public.apply_purchase(uuid, text, text, text, text, text, timestamptz, timestamptz)
  from public, anon, authenticated;
grant execute on function public.apply_purchase(uuid, text, text, text, text, text, timestamptz, timestamptz)
  to service_role;

-- What the app shows: your plan and today's usage, as
-- {plan, source, product_id, expires_at, used, limit, resets_at, private, voice}.
-- source, product_id and expires_at are null on Free.
create or replace function public.my_plan()
returns jsonb
language plpgsql stable security definer
set search_path = public
as $$
declare
  v_me   uuid := auth.uid();
  v_day  date := public.plan_day(now());
  v_plan text;
  v_row  public.plans%rowtype;
  v_used integer;
begin
  if v_me is null then
    raise exception 'my_plan: sign in first' using errcode = '28000';
  end if;
  v_plan := public.effective_plan(v_me);
  select * into v_row from public.plans where user_id = v_me;
  select coalesce(sum(u.messages), 0) into v_used
    from public.plan_usage u where u.user_id = v_me and u.day = v_day;
  return jsonb_build_object(
    'plan', v_plan,
    'source', case when v_plan = 'free' then null else v_row.source end,
    'product_id', case when v_plan = 'free' then null else v_row.product_id end,
    'expires_at', case when v_plan = 'free' then null else v_row.expires_at end,
    'used', v_used,
    'limit', public.plan_limit(v_plan),
    'resets_at', public.plan_resets_at(v_day),
    'private', v_plan <> 'free',
    'voice', v_plan = 'pro');
end;
$$;

revoke execute on function public.my_plan() from public, anon;
grant execute on function public.my_plan() to authenticated, service_role;
