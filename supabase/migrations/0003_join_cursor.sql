-- A new member's read cursor starts just before the chat was created, so
-- every message (even one written in the same instant as the chat) counts
-- as unread and their first Catch me up covers the whole history.

create or replace function public.join_chat(p_code text)
returns public.chats
language plpgsql security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  code text := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
  c public.chats;
begin
  if me is null then raise exception 'Not signed in'; end if;
  if (select count(*) from public.join_attempts
       where user_id = me and created_at > now() - interval '1 hour') >= 15 then
    raise exception 'Too many wrong codes. Try again in an hour.';
  end if;
  select * into c from public.chats where invite_code = code;
  if not found then
    -- Return instead of raising: a raise would roll back this counter row.
    -- The client reads an all-null row as "no chat with that code".
    insert into public.join_attempts (user_id) values (me);
    return null;
  end if;
  if (select member_count from public.chats where id = c.id) >= 64 then
    raise exception 'That chat is full';
  end if;
  insert into public.chat_members (chat_id, user_id, last_read_at)
  values (c.id, me, c.created_at - interval '1 millisecond')
  on conflict (chat_id, user_id) do nothing;
  select * into c from public.chats where id = c.id;
  return c;
end;
$$;
