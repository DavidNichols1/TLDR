-- Cetchup schema, part 11: the Terms of Service and Privacy Policy you agreed
-- to (written Nov 4, 2026). One part, to apply as 0011_terms.
--
-- terms_acceptances: one row per person, the version of the terms they last
--   agreed to and when. A version is the date the terms were published
--   ("2026-11-04"), so versions sort as text. The policies are at
--   https://cetchup.ai/terms and https://cetchup.ai/privacy, and the version
--   the apps show is in their config (iOS Config.termsVersion, Android
--   Config.TERMS_VERSION).
--   * The sign-in screen says "By continuing, you agree to Cetchup's Terms of
--     Service and Privacy Policy", and the apps call accept_terms right after
--     every sign-in, with the email code or a password.
--   * Someone signed in with no row, or a row older than the app's version
--     (the terms changed), gets a one-time sheet before the app whose Agree
--     calls accept_terms too.
--   * You read only your own row. Nobody writes the table from the app:
--     accept_terms (security definer) writes yours, for auth.uid() only, at
--     the server's time, so an acceptance can't be made for someone else or
--     backdated. There's no withdrawing it; deleting your account deletes it.
--
-- Who has agreed to what, in the SQL editor:
--   select version, count(*) from public.terms_acceptances group by 1 order by 1 desc;

create table public.terms_acceptances (
  user_id     uuid primary key references auth.users(id) on delete cascade,
  version     text not null
    constraint terms_acceptances_version_check check (version ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'),
  accepted_at timestamptz not null default now()
);

alter table public.terms_acceptances enable row level security;
revoke all on public.terms_acceptances from public, anon, authenticated;
grant select on public.terms_acceptances to authenticated;

create policy terms_acceptances_select_own on public.terms_acceptances
  for select to authenticated
  using (user_id = (select auth.uid()));

-- Records that you agree to the terms of p_version, now. Agreeing again
-- (every sign-in does) moves your row to that version and time. Returns
-- {version, accepted_at}.
create or replace function public.accept_terms(p_version text)
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  v_me  uuid := auth.uid();
  v_row public.terms_acceptances%rowtype;
begin
  if v_me is null then
    raise exception 'accept_terms: sign in first' using errcode = '28000';
  end if;
  if p_version is null or p_version !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
    raise exception 'accept_terms: a version is a date, like 2026-11-04' using errcode = '22023';
  end if;
  insert into public.terms_acceptances as t (user_id, version, accepted_at)
  values (v_me, p_version, now())
  on conflict (user_id) do update
    set version = excluded.version, accepted_at = excluded.accepted_at
  returning * into v_row;
  return jsonb_build_object('version', v_row.version, 'accepted_at', v_row.accepted_at);
end;
$$;

revoke execute on function public.accept_terms(text) from public, anon;
grant execute on function public.accept_terms(text) to authenticated;
