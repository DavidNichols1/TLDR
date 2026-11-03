-- Ketchup speed, part 4: indexes measured against the app's hot paths.
--
-- Timed Nov 3, 2026 with EXPLAIN ANALYZE (median of 7 runs, as the signed-in
-- reader under RLS where the app reads that way) on today's data and on a
-- busy account built inside a transaction that was rolled back: a
-- 20,000-message chat with 5,000 unread, 20 more chats of 300 messages, and
-- 3,000 saved briefs. Only indexes that changed a number are here.
--
-- Already on the right index, nothing to add: opening a chat (newest 327 by
-- messages_chat_time_idx, 0.38 ms at scale), its members (chat_members_pkey,
-- 0.58 ms), catch-up's unread read (0.49 ms) and its saved-brief lookup
-- (0.02 ms).

-- Every send: enforce_message_hygiene counts the sender's messages from the
-- last 10 seconds. With only messages_sender_idx the planner walked
-- messages_chat_time_idx instead: 0.80 ms at 26,000 messages, growing with
-- the whole table. With this index: 0.015 ms, however big it gets.
create index if not exists messages_sender_time_idx
  on public.messages (sender, created_at desc);

-- catch-up's hourly cap counts your briefs from the last hour: 0.11 ms ->
-- 0.016 ms at 3,000 briefs (ai_briefs_owner_idx has chat_id in the middle).
create index if not exists ai_briefs_user_time_idx
  on public.ai_briefs (user_id, created_at desc);

-- The performance advisor's unindexed foreign key: deleting an account sets
-- its chats' created_by to null without reading every chat. created_by never
-- changes, so this costs nothing per message. Not last_message_sender: the
-- send trigger rewrites it on almost every message, and indexing it would
-- stop those updates from staying in place (HOT) to speed up a rare delete.
create index if not exists chats_created_by_idx
  on public.chats (created_by) where created_by is not null;
