-- Ketchup schema, part 7: people. Your account now; the people you block,
-- report and keep as contacts come in later parts of this file.
--
-- Applied live in parts, one apply_migration per slice of the people work,
-- each named 0007_people_<part>. This file is all of them, in order, so a
-- fresh project gets everything from one `supabase db push`:
--   0007_people_account   delete_account()

-- ---------------------------------------------------------------------------
-- Part 1: delete account (App Store guideline 5.1.1(v)).
--
-- Settings → Delete account calls delete_account(), one transaction:
--   * Friends' saved catch-ups and answers in chats this person wrote in are
--     deleted, so their words don't outlive them inside someone else's
--     summary. The next Catch me up reads the chat fresh.
--   * Deleting the auth user cascades to the profile, every membership (a
--     chat they were the last one in goes too, through apply_member_change),
--     every message they sent, their own briefs, join attempts and text usage.
--   * Chats they wrote in get their inbox line (last message, preview,
--     sender) recomputed from what's left, so no preview quotes them.
-- Their messages go with them instead of staying behind as "Deleted account":
-- what someone wrote is theirs, and a message with the name taken off still
-- says who wrote it in a group of friends. The others keep the chat.

create or replace function public.delete_account()
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  touched uuid[];
begin
  if me is null then raise exception 'Not signed in'; end if;

  select coalesce(array_agg(distinct t.chat_id), '{}') into touched
    from (select chat_id from public.messages where sender = me
          union
          select chat_id from public.chat_members where user_id = me) t;

  delete from public.ai_briefs b
   where b.user_id <> me
     and b.chat_id = any (touched)
     and exists (select 1 from public.messages m
                  where m.chat_id = b.chat_id and m.sender = me and m.created_at <= b.until);

  delete from auth.users where id = me;

  update public.chats c
     set (last_message_at, last_message_preview, last_message_sender) =
         (select m.created_at, left(m.body, 140), m.sender
            from public.messages m
           where m.chat_id = c.id
           order by m.created_at desc
           limit 1)
   where c.id = any (touched);
end;
$$;

revoke execute on function public.delete_account() from public, anon;
grant execute on function public.delete_account() to authenticated;
