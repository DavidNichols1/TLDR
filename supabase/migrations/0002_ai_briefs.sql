-- TL;DR schema, part 2: what Muse Spark produced.
--
-- Every Catch me up and every question asked of a chat is stored, so:
--   * a reopened brief shows instantly instead of calling the model again;
--   * plans can be added to the calendar later from the saved card;
--   * the demo can show the model's structured output next to the chat.
-- Rows are private to the member who asked. Only the `catch-up` edge
-- function writes them (service role, after it has checked membership);
-- clients can read their own and nothing else.

create table public.ai_briefs (
  id            uuid primary key default gen_random_uuid(),
  chat_id       uuid not null references public.chats(id) on delete cascade,
  user_id       uuid not null references public.profiles(id) on delete cascade,
  kind          text not null constraint ai_briefs_kind_check check (kind in ('catch_up', 'ask')),
  question      text constraint ai_briefs_question_check check (question is null or char_length(question) <= 500),
  since         timestamptz,          -- first message covered (exclusive cursor the user had)
  until         timestamptz not null, -- newest message covered
  message_count integer not null default 0,
  model         text not null,
  result        jsonb not null,
  latency_ms    integer,
  created_at    timestamptz not null default now()
);

create index ai_briefs_owner_idx on public.ai_briefs (user_id, chat_id, created_at desc);
create index ai_briefs_chat_idx  on public.ai_briefs (chat_id);

alter table public.ai_briefs enable row level security;
revoke all on public.ai_briefs from public, anon, authenticated;
grant select on public.ai_briefs to authenticated;

create policy ai_briefs_select_own on public.ai_briefs
  for select to authenticated
  using (user_id = auth.uid() and public.is_chat_member(chat_id));

-- Model calls cost money: at most 60 briefs per person per hour.
create or replace function public.ai_brief_quota_ok(p_user uuid)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select (select count(*) from public.ai_briefs
           where user_id = p_user and created_at > now() - interval '1 hour') < 60;
$$;
revoke execute on function public.ai_brief_quota_ok(uuid) from public, anon, authenticated;
