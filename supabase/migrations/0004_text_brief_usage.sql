-- Ketchup schema, part 4: usage counts for catch-up-text.
--
-- catch-up-text (the experimental, unreleased Instagram catch-up) stores
-- nothing from the conversations it reads, so unlike catch-up it can't count
-- ai_briefs rows for its hourly cap. It counts these rows instead: who, when,
-- which source and mode, and how many messages. Never any text, names or
-- results.
-- Only the edge function writes them (service role, through take_text_brief).
-- Clients get no access at all, like join_attempts.

create table public.text_brief_usage (
  id            bigint generated always as identity primary key,
  user_id       uuid not null references public.profiles(id) on delete cascade,
  source        text not null constraint text_brief_usage_source_check check (source in ('instagram')),
  mode          text not null constraint text_brief_usage_mode_check check (mode in ('catch_up', 'ask')),
  message_count integer not null constraint text_brief_usage_count_check check (message_count between 0 and 600),
  created_at    timestamptz not null default now()
);

create index text_brief_usage_user_time_idx on public.text_brief_usage (user_id, created_at desc);

alter table public.text_brief_usage enable row level security;
revoke all on public.text_brief_usage from public, anon, authenticated;

-- Checks the cap and records one use in the same transaction. The advisory
-- lock makes two requests at once from one person take turns, so they can't
-- both squeeze in under the limit.
create or replace function public.take_text_brief(
  p_user uuid, p_source text, p_mode text, p_messages integer, p_limit integer)
returns boolean
language plpgsql security definer
set search_path = public
as $$
begin
  perform pg_advisory_xact_lock(hashtextextended('take_text_brief:' || p_user::text, 0));
  if (select count(*) from public.text_brief_usage
       where user_id = p_user and created_at > now() - interval '1 hour') >= p_limit then
    return false;
  end if;
  insert into public.text_brief_usage (user_id, source, mode, message_count)
  values (p_user, p_source, p_mode, p_messages);
  return true;
end;
$$;

revoke execute on function public.take_text_brief(uuid, text, text, integer, integer) from public, anon, authenticated;
grant execute on function public.take_text_brief(uuid, text, text, integer, integer) to service_role;
