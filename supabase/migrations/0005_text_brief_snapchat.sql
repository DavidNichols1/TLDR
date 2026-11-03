-- Ketchup schema, part 5: catch-up-text also reads Snapchat chats.
--
-- The experimental, unreleased web-chat catch-up now has a second source,
-- Snapchat for Web (ios/Ketchup/WebChat/). Its usage rows count toward the
-- same hourly cap and, like Instagram's, carry no text, names or results.

alter table public.text_brief_usage
  drop constraint text_brief_usage_source_check,
  add constraint text_brief_usage_source_check check (source in ('instagram', 'snapchat'));
