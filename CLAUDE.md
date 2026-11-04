# Ketchup: notes for Claude sessions

Hackathon app (Meta Global AI Developer Hackathon, due Nov 4, 2026 9 PM ET). Product context
lives in the Brain vault note `Projects/Meta Hackathon/Meta Hackathon.md`; this file is
the technical recipe. README.md is the judge-facing overview.

## Rules
- The app was called TL;DR until Nov 2, 2026, then renamed Ketchup (as in *catch up*). On purpose,
  three things kept the old name: the `tldr` JSON field (stored data), the seed accounts'
  `tldr.demo+…` emails (live users), and the comments in applied migrations.
- No em dashes in anything user-facing: UI copy, Muse Spark output (brief.ts `plain()` strips
  them), docs.
- The repo is **public**. No secrets, ever: the Meta key is only the Supabase secret
  `META_API_KEY`; the service-role/secret key is only in the gitignored
  `scripts/seed-demo/.env`. The app ships only the publishable key (Config.swift).
- Must genuinely use the Meta Model API (Muse Spark). Don't swap in another model.
- Commit and push small, often: the history shows the work happened during the event.

## Backend (Supabase ref `cfqlnthmqwkhjbhylvgu`, still named "TLDR" in the dashboard)
- Migrations in `supabase/migrations/` are also applied live (Supabase MCP
  `apply_migration`); keep both in step. RLS is the security boundary.
- RLS tests: run `supabase/tests/rls_check.sql` via `execute_sql` (rolls back; expect all checks pass).
- Speed check: run `supabase/tests/speed_check.sql` via `execute_sql` (rolls back). It times the
  hot paths (open a chat, members, `my_chats()`, catch-up's reads, its hourly cap, every send's
  rate check) on today's data and on a busy account it builds and throws away, and names the
  index each used. Compare with the numbers in `0008_speed_indexes.sql` after a schema change.
- Deploy the edge function without Docker:
  `supabase functions deploy catch-up --project-ref cfqlnthmqwkhjbhylvgu --use-api`
  (verify_jwt stays on). Check with `list_edge_functions` → `verify_jwt: true`, and an
  unauthenticated POST must return 401.
- Muse Spark: `supabase/functions/_shared/muse.ts`, `POST https://api.meta.ai/v1/chat/completions`,
  model `muse-spark-1.3` (override with `META_MODEL`), docs at https://dev.meta.ai/docs. Every
  plan uses it (Standard mode). Never `muse-spark-1.3-contributor` for chats: Meta's terms, section
  6.2, ban personal information in Contributor mode. See "Plans, consent and purchases".
- Logs for a catch-up call: Supabase MCP `query_logs`, source `function_logs`; each Muse call
  logs `{mode, attempt, messages, prompt, completion, reasoning}` token counts. Latency is in
  `ai_briefs.latency_ms`. Keep `META_REASONING=low` (minimal invented a plan time on Nov 2).
- The app prefetches a catch-up when a chat opens with 15+ unread (ChatModel.open); the read
  cursor moves only when the user opens the result.
- Check secrets by name only: `supabase secrets list --project-ref cfqlnthmqwkhjbhylvgu`
  (run it from the repo root; it writes a `supabase/.temp` cache that is gitignored there).
- `enforce_message_hygiene` forces `messages.created_at = now()` on insert; the seed
  backdates with an update afterwards.

## "Maya joined" (migration 0009)
- `0009_joins.sql`, one part, applied live as `0009_joins`. `join_chat`, `create_chat` and
  `create_chat_with` write a `messages` row with `kind = 'joined'` (body "joined", sent as
  the person who joined) through `post_joined()`, which clients can't call. Clients can't
  set `kind` (no column grant), and `messages_insert_member` takes only `kind = 'text'`.
- A join line is never unread (`my_chats`, catch-up, both apps), never the inbox line
  (`apply_message` skips it, and so do `my_chats`' block fallback and `delete_account`),
  never moves the joiner's read cursor, and never counts toward or trips the send limit.
  One per person per chat: rejoining replaces the old line; joining a chat you're already
  in writes nothing. Nothing was backfilled. A block hides it like a message.
- The apps and catch-up read messages with `select=*`, so either side of 0009 works.
  catch-up puts a join in the transcript as `[Maya joined]` with no ref: never cited, never
  in `message_count`. Apps from before 0009 show it as a plain "joined" bubble.
- Apps: iOS `Message.isJoin`, `JoinedLine` (Chat/ThreadDivider.swift) and `ChatView.rows`;
  Android `Message.isJoin`, `JoinedLine` and `threadRows` (ui/chat/ThreadPieces.kt). The
  "N new" line goes above a join line that's after your cursor, but the count leaves it out.
  Previews: iOS `-screen chat-joined`, Android `--es screen chat-joined` (Rowan, made up,
  joins Breck and says hi).
- Checks: the RLS suite's `joins:` section (95 of 95 with 0009 applied inside the rolled-back
  transaction, Nov 3, 2026), `deno test supabase/functions/_shared/` (12), and the speed
  check (the busy account's inbox 2.60 ms before, 2.59 ms after).
- Order: apply the migration, then redeploy `catch-up` (and `catch-up-text`, since
  `_shared` changed). Between the two, the old catch-up reads a join as a message.

## iOS (`ios/Ketchup.xcodeproj`, scheme `Ketchup`, bundle `com.vibetemp.ketchup`, team GBXTAWLQK5)
- Build into default DerivedData (never under ~/Desktop):
  `cd ios && xcodebuild -project Ketchup.xcodeproj -scheme Ketchup -destination 'id=<sim udid>' build`
  (`xcrun simctl list devices available` for the udid; the iPhone 17 Pro sim works).
- Then the iOS Simulator MCP: `launch` with the built `Ketchup.app`, `screenshot`.
- David signs in himself (email + 8-digit code; `Config.otpLength` must match Auth → Email OTP Length); never type his email or codes.
- Sign-in needs `{{ .Token }}` in the Magic Link and Confirm signup email templates (set Nov 2, 2026). Email goes out through Resend SMTP from noreply@vibetemp.com (30/hour cap).

## Design system and offline previews
- `docs/DESIGN.md` is the design system (a diner counter: cream, ink, ketchup, mustard, pickle).
  Colors, type and motion live in `Theme.swift`; shapes, buttons and labels in `ios/Ketchup/Design/`.
  The old purple names (`Theme.accent`, `aiGradient`, ...) are deprecated aliases until every screen is restyled.
- DEBUG builds open one screen on fixtures with `-screen <name>`, for example
  `xcrun simctl launch <udid> com.vibetemp.ketchup -screen list` (tap a name), `chat`, `ai-catchup`, `design`.
  No sign-in or network: `Supabase.rest`/`sendAuth` and Realtime refuse to connect while previewing.
  Data: `Debug/PreviewData.swift` over `Debug/Fixtures/`; screens: `Debug/CorePreviewScreen.swift`, `Debug/AIPreviewScreen.swift`.
- Keep preview code inside `#if DEBUG`; a Release build (`-configuration Release CODE_SIGNING_ALLOWED=NO`) must still compile.

## Home tabs (`ios/Ketchup/Views/HomeTabs.swift`, since Nov 3, 2026)
- After sign-in the home is a tab bar along the bottom: Chats, Instagram, Snapchat, You
  (`HomeTab.all`; another chat app is one more `.web(…)`). It replaced the top swipe pager.
  The bar is ours, not the system's glass: cream, a hairline, ink, a mustard mark under the
  current tab, the inbox's unread count on Chats, your photo as You's icon. It stops growing
  at Extra Extra Large text (long press shows a tab big). The app reopens on the last tab
  (`home.page`).
- Every tab is built the first time it's opened, then kept (hidden by opacity, never torn
  down), so the Instagram and Snapchat web views load once and keep their place and sign-in.
  Chats and You are each their own hosting root (`HostedPage`), full screen, so a chat's
  input bar meets the keyboard as on a whole screen; a hidden root takes no touches. The web
  tabs stay plain views between the status bar and the bar, and the home ignores the
  keyboard, so a site's page keeps its size under it as in Safari (WebKit moves it).
- While a chat is open the bar steps aside (`HomeTabsState.locked`, set by ChatsListView)
  and the chat gets the whole screen. The inbox keeps its last row clear of the bar with
  `safeAreaPadding`; You's pages get the bar as safe area (`additionalSafeAreaInsets`).
- Previews: `home` (Chats), `home-instagram`, `home-snapchat` and `home-you`; the web tabs
  open their synthetic threads (add `-webchat.instagram.introSeen YES`, or snapchat, to skip
  the first-visit card). `-openChat YES` opens Breck 1.2 s in, so the bar steps aside.
- Checked Nov 3, 2026 on the iPhone 17 Pro Max sim (iOS 27) with a temporary DEBUG probe
  (since removed) that switched tabs 8 times on a timer: each web view loaded once and stayed
  the same instance, a touch at mid-screen always reached the visible tab, the chat's field
  moved from y 883 to 570 with the keyboard at 609 (once, not twice), and You's safe area
  bottom was 90.3 pt (34 + the 56.3 pt bar). Not checked: typing into a site's message box
  (needs a real tap) and the real sites.

## Kept on the phone, and skeletons (`ios/Ketchup/Store/`, `Design/Skeletons.swift`)
- `DeviceStore` keeps the inbox (`inbox.json`: the my_chats rows and your profile) and each
  chat's newest 400 messages and members (`threads/<chat>.json`) in
  `Application Support/Ketchup/<user id>/`: complete-until-first-unlock, out of backups.
  Sign-out deletes the whole folder, launch deletes any other user's, and each inbox refresh
  forgets chats you're no longer in. Dates are stored as numbers, and `version` guards the shape.
- AppModel and ChatModel restore it in their inits, and the server replaces it. ChatModel's
  first page drops kept messages it didn't send back (`ThreadSnapshot.reconcile`), then takes
  your read cursor from your member row and pages back to it, so a stale kept inbox can't hide
  unread (the seed's `--rearm`). Only then is `synced` set: ChatView places the thread and starts
  counting what's been seen (`sawBottom`), so backing out of a stale copy marks nothing read.
  A current kept copy is scrolled into place earlier, without that. Until `synced`, the poll loop
  retries the first page every 4 s, whether or not Realtime is live. A send, a catch-up or
  reaching the bottom records `readThrough`, and unread counts from the later of it and the
  server's cursor, so a page or member row that answers after you sent can't bring the count
  back. Check it offline: `-screen chat-kept -send "on my way"` must drop "302 new" for good
  (the bubble shows, not sent), and `-screen chat-kept` alone must keep "302 new".
- `Profile`, `ChatSummary`, `Member` and `Message` are `Codable` for this: new fields are kept
  automatically and must be Codable too.
- Saved catch-ups (`Store/SavedBriefs.swift`, `saved/<chat>.json` or `saved/web-<source>.json`):
  ChatModel keeps a catch-up once you've seen it (a prefetch only when you open it) and every
  answer; WebCatchUp keeps Instagram's and Snapchat's, on the phone only. The server's
  `brief_id` keeps a reopened catch-up from being kept twice. Each chat keeps its last 3
  catch-ups and its last 3 answers, newest first, each kind on its own so asking never pushes a
  catch-up out (`DeviceStore.savedPerChat`, `newest`); a web file holds every thread of its
  source, so there it's 3 of each per thread. A list kept under the old cap of 100 shrinks the
  first time it's read and is written back. Each keeps the messages it cites (`SavedQuote`) and,
  for a catch-up, the newest message it read (`until`; older saves have none). UI in
  `Saved/SavedCatchUps.swift`: "Earlier catch-ups" in the chat's and the web pages' … menu and
  under a chat's catch-up (`EarlierCatchUpsRow`, a sheet over the brief; a source in it closes
  both and jumps), and Settings' "Saved catch-ups" and "Clear cache" rows (`savedCatchUpsSlot`).
  Clear cache runs `DeviceStore.clearCopies()` and `RemoteImages.clear()`; saved catch-ups stay.
  Deletes go through the store's queue with a marker in memory, so a read in between can't bring
  a file back. Blocking someone still drops every saved catch-up in the chats you share
  (`PeopleStore.block`), sign-out still wipes them, and leaving a chat still leaves them.
- Nothing new since the last catch-up: Catch me up shows the newest one kept for that chat
  ("Nothing new since 2:14 PM. Here's your last catch-up.", `NothingNewNote` over it) and calls
  nothing, not even the edge function. `ChatModel.catchUpIfNeeded` decides it when the first page
  is in (`synced`), nothing is unread and nobody else has written after the kept one's `until`
  (`keptCatchUpIfNothingNew`, `hasNewMessages(since:)`); it sets `catchUp` to `.nothingNew`, the
  same envelope the server sends when nothing is unread. When the server says that itself (new
  messages came in and you've read them), the sheet shows the kept one too, with "Nothing
  unread." "You're all caught up" is only for a chat with no catch-up kept. With nothing unread,
  the bar offers "Your catch-up" when one is kept (`CatchUpBar(hasKept:)`). The server's dedupe
  and cache (`once.ts`) are untouched: anything new still goes through them. Check offline:
  `-screen brief-nothing-new` must show the note over Breck's catch-up and print `[catch-up]
  nothing new since the kept catch-up, showing it with no call`; its Muse Spark call is set to
  fail, so a call that shouldn't happen shows as an error card.
- No duplicate calls. Server: `_shared/once.ts` (in `catch-up`): a pending `ai_briefs` row
  (`model = 'pending'`) whose id hashes user, chat, kind, since, until and question claims the
  brief; the primary key lets one insert win, the others poll it (800 ms) and return it as saved;
  a failed call deletes its claim, a dead one goes stale after 120 s. `deno test
  supabase/functions/_shared/` covers it with a stand-in table. App: `Net/InFlight.swift` shares
  identical GETs and `my_chats` (`Supabase.rest(shares:)`); the prefetch only starts if no tap
  has; create and join ignore a second tap while busy. Live test: a signed-in DEBUG build's
  Settings › "Test: two identical asks at once" asks `catch-up` the same question twice together;
  both answers should carry one brief id, and the function log one Muse Spark call.
- Offline check, no sign-in: `-screen store-check` must show "16 of 16 passed, 1 skipped" on a
  simulator (data protection only exists on a phone, where it's 17 of 17); the console prints
  `[store-check] PASS …`. DEBUG builds log reads as `[store] read a thread, 74 KB in 0.9 ms`.
- The files on a simulator: `xcrun simctl get_app_container <udid> com.vibetemp.ketchup data`,
  then `Library/Application Support/Ketchup/`.
- At once, the server following (slice 5): `AppModel.leave(_:)` takes the chat out of the inbox
  and off the phone before `leave_chat` answers (a refresh meanwhile can't bring it back), and
  `renameNow(to:)` (Settings) shows the new name before the server has it; a refusal puts it
  back and sets `app.problem`, which the inbox and Settings show. The first-run name step still
  waits (`rename(to:)`). Check offline: `-screen home -leave YES` and `-screen settings -renameTo
  Dave`, each with and without `-serverRefuses YES` (Debug/PreviewActions.swift).
- Previews: `inbox-loading`, `chat-loading`, `ai-loading-blank` (skeletons; `-reduceMotion YES`
  holds them still), `chat-kept` (a live ChatModel opening on a kept copy with no server, in
  a scratch folder, never the real one), and `saved`, `saved-brief`, `saved-empty`,
  `saved-quote`, `saved-all` (a scratch store with Breck's catch-up, two answers and the
  Instagram test thread's catch-up). `settings -section phone` shows the two Settings rows.
  The `brief-` previews keep Breck's last 3 catch-ups (Muse Spark's real one and two written by
  hand; a fourth falls off) and an answer, in DeviceStore.shared's preview folder as a made-up
  user: `brief-history` (Earlier catch-ups over a new catch-up), `brief-nothing-new` (add
  `-section earlier` for the row under it) and `brief-chat` (the thread, all read, with "Your
  catch-up" in the bar, to tap through). Screenshots: `docs/screens/speed/`.

## Demo seed
`scripts/seed-demo/README.md`. 302-message "Breck Weekend 🎿" chat from 5 test accounts;
the viewer sets display name **David**, joins with the printed invite code, and has
302 unread (once 0009 is applied, joining also leaves a "David joined" line; the seed keeps
it out of the inbox line and its counts, and moves one stranded mid-chat by `--retime` to
the chat's start). `--rearm` resets David to all-unread between video takes. `--photos` (opt-in,
safe to re-run) adds two made-up photos on the last day, so a catch-up can cite one: 304 unread.

## Plans, consent and purchases (migration 0010, written Nov 3, 2026, not applied yet)
Free 150, Plus 400 ($4.99/month) and Pro 1,000 ($9.99/month) messages Muse Spark reads for you a
day. Every plan is Standard mode `muse-spark-1.3`, which Meta doesn't train on; Pro adds Listen (the
phone's own voice; Meta has no text to speech). Plus and Pro are Apple auto-renewable subscriptions
in one group (StoreKit 2). Code: `supabase/functions/_shared/` (`consent.ts`, `plan.ts`, `apple.ts`,
`purchase.ts`), `supabase/functions/verify-purchase/`, `ios/Ketchup/Plans/`, Android
`data/ConsentGate.kt` and `ui/plans/ConsentDialog.kt`.
- **Consent** (`ai_consents`, one row per person): your yes to Ketchup sending the messages a
  catch-up or question covers, friends' included, to Meta's Muse Spark, and that you're 18 or older
  (Meta's terms 10.1; Apple 5.1.2(i)). RLS: your own row only; insert names only `user_id` and
  `confirmed_adult`, so `consented_at` is always the server's; delete withdraws. `my_plan()` reports it.
- **Allowance** (`plan_usage`, no client access): a call is charged the messages it sends Muse Spark
  (catch-up: the unread ones; Ask: every message it searches, up to 800; catch-up-text: the thread),
  at least 10 (`CALL_FLOOR` in `plan.ts`: each call has a fixed cost). The day is Denver's
  (`plan_day()`), so a phone's time zone can't reset it. `take_plan_usage` checks and spends in one
  step under a per-person advisory lock; over the limit it's a 402 `{error, kind: "plan_limit", plan,
  used, limit, needed, resets_at}` and nothing is counted. Limits live in `plan_limit()`; the app's
  cards repeat them (`Plans/PlanModels.swift`). Note: Ask on the 302-message demo chat costs 302.
- **Every place the checks sit** (the server decides; the apps only make it friendly):
  - consent, 403 `kind: "consent_required"` until there's a row: `catch-up/index.ts` right after the
    caller is known (before membership); `catch-up-text/index.ts` right after the caller is known.
  - allowance: `catch-up/index.ts` after `once()`, so saved and shared briefs are free (a 402 releases
    the claim); `catch-up-text/index.ts` before `take_text_brief` (given back on its 429 or 500). Both
    give the messages back when Muse Spark fails.
  - iOS: `Net/Supabase.swift` `function()` → `PlanGate.beforeMuse` for catch-up and catch-up-text (the
    consent sheet over the sheet you're in; a prefetch never asks, and on Free it waits for your tap so
    opening chats doesn't spend the 150); `throwIfError` → `PlanGate.serverRefused` (a 402 opens the
    paywall over the catch-up you're reading; a 403 consent_required forgets a stale yes).
  - Android: `SupabaseClient.function()` → `ConsentGate.call`, switched on in `BriefActivity` (every
    brief, from a chat or the reader bubble), with `ConsentDialogHost()` there. No purchases on Android
    (sideloaded); a 402 or 403 shows the server's sentence as is.
- **verify-purchase** (verify_jwt on) takes `{jws}`, StoreKit's `jwsRepresentation`. `apple.ts` checks
  the x5c chain to the pinned Apple Root CA - G3 (public; SHA-256 `63343abf…653e9179`), Apple's OIDs on
  the intermediate (`1.2.840.113635.100.6.2.1`) and leaf (`1.2.840.113635.100.6.11.1`), dates at
  `signedDate`, and the ES256 signature, with WebCrypto and no dependencies (no OCSP). `purchase.ts`
  checks bundle `com.vibetemp.ketchup`, the two product IDs, the type, and `appAccountToken` (the app
  buys with the user id; another account's is a 409). Production → `source 'app_store'`; Apple's
  sandbox (TestFlight, App Review, sandbox testers) → `'sandbox'`. `apply_purchase` (service role):
  newer replaces older, a refund ends it, one subscription unlocks one account. The app sends every
  transaction it sees (a purchase, `Transaction.updates`, Restore, entitlements at sign-in) and
  finishes it once the server has it. Not built: App Store Server Notifications (a renewal or refund
  made while the app is closed shows up when it next opens).
- **`STOREKIT_XCODE_TEST`** (function secret; off unless exactly `true`). Xcode's local StoreKit test
  (`Plans/Ketchup.storekit`) signs with a certificate Xcode makes (`kid: Apple_Xcode_Key`, one cert), so
  Apple's chain can't vouch for it. With the flag on, verify-purchase accepts a transaction whose
  environment is `Xcode`, for this bundle and one of the two products (and this account, when it
  carries a token), as `source 'xcode-test'`, for at most 24 hours (capped in `apply_purchase` and by
  a check constraint). **While it's on, anyone signed in can make one up and get Plus or Pro for a
  day.** David turns it on only while recording, then unsets it:
  `supabase secrets set STOREKIT_XCODE_TEST=true --project-ref cfqlnthmqwkhjbhylvgu`, then
  `supabase secrets unset STOREKIT_XCODE_TEST --project-ref cfqlnthmqwkhjbhylvgu`. A made-up Sandbox or
  Production purchase fails either way (`apple_test.ts` shows both).
- **`PLANS_ENFORCED=false`** (function secret): the emergency off switch. Nothing counted or refused;
  consent is still required.
- **Apply and deploy, in this order**: 1. migration as one part, `apply_migration` name `0010_plans`,
  then `rls_check.sql` (132 of 132 on Nov 3, 2026, inside a rolled-back transaction). 2. Give the
  recording account Pro and consent (the SQL in the migration's header, plus
  `insert into public.ai_consents (user_id, confirmed_adult) values ('<id>', true);`): the demo
  chat's 302 unread is over Free's 150. 3. Install the new iOS and Android builds (old builds can't
  say yes, so after step 4 they get the 403's sentence). 4. Deploy `catch-up`, `catch-up-text` and
  `verify-purchase` with `--use-api`; `list_edge_functions` → `verify_jwt: true` on all three, and an
  unauthenticated POST to `verify-purchase` returns 401. Until step 1 the iOS app shows no plan rows
  and asks nothing (`my_plan` missing), and Android asks nothing (no `ai_consents` table).
- **Tests**: `deno test supabase/functions/_shared/` (37 on Nov 3, 2026: `plan_test.ts`,
  `consent_test.ts`, `apple_test.ts` with Apple's real G6 intermediate checked against the pinned root
  and a throwaway chain made at test time, nothing private in the repo). Android `ConsentGateTest`,
  `PlanRefusalsTest`.
- **StoreKit on the simulator.** From Xcode, Run uses `Plans/Ketchup.storekit` (the scheme's StoreKit
  Configuration; set it to None to use Apple's sandbox instead). Without Xcode, in a DEBUG simulator
  build: `SIMCTL_CHILD_DYLD_FRAMEWORK_PATH=/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/Library/Frameworks xcrun simctl launch <udid> com.vibetemp.ketchup -storekitTest YES -screen paywall -buy plus`
  (`Plans/StoreKitTesting.swift` starts an `SKTestSession` on the bundled file; the framework path
  lets it find XCTest, or it prints why and does nothing). `-buy plus` presses Get Plus 1.5 s in and
  StoreKit's sheet appears ("For testing purposes only"); add `-storekitDialogs NO` to skip it. The
  transaction's JWS lands in the app container's `tmp/storekit-test-last.jws` for checking against
  `checkPurchase` (Nov 3, 2026: Apple's chain refused it, flag off 403, flag on Plus `xcode-test`,
  another account 409). Release builds leave `Ketchup.storekit` out (`EXCLUDED_SOURCE_FILE_NAMES`).
- **Previews**: `paywall`, `plan-free-usage` (Settings' Plan section and bar), `plan-limit-hit` (Breck's
  302 turned down on Free, paywall over it), `consent`, `plan-listen` (Pro's Listen). Screenshots:
  `docs/screens/plans/`.
- **App Store Connect (David)**: see README, "Plans". The product IDs are
  `com.vibetemp.ketchup.plus.monthly` (level 2) and `com.vibetemp.ketchup.pro.monthly` (level 1).

## Settings and people (migration 0007)
Code: `ios/Ketchup/People/` (`SettingsView`, `AccountPages`, `SettingsPieces`, `Account.swift`,
`ProfileView`, `ReportView`, `BlockedPeopleView`, `PeopleView` with `PeoplePicker` and `PeopleList`,
`InviteView`, `YouView`, `PeopleStore`, `PeopleModels`),
`Net/PeopleAPI.swift`, `WebChat/WebChatSignOut.swift`, edge functions `delete-account` and
`report-alert`. The You tab (`YouView`) is your photo, name and email
(`AccountHeader`, shared with Settings), your people (`PeopleList`), Invite friends, Blocked
people (`PrivacySection`) and a Settings row. Settings opens from it as a sheet; signing out waits
for the sheet to close (`SettingsExit`, the sheet's `onDismiss` in `YouView`), so it can't be
left over sign-in.
- `0007_people.sql` is one file applied live in parts, one `apply_migration` per slice, each
  named `0007_people_<part>` (so far `0007_people_account`, `0007_people_account_photos`,
  `0007_people_blocks_reports`, `0007_people_reports_index`, `0007_people_delete_files`,
  `0007_people_contacts`, `0007_people_inbox_speed`). Append, never rewrite: a fresh project
  runs the whole file once.
- Delete account is the `delete-account` edge function (verify_jwt on): it calls
  `delete_account()` as the person (security definer, `authenticated` only), which deletes
  friends' saved catch-ups that read their messages, then the auth user (profile,
  memberships, messages, own briefs cascade; a chat they were last in goes through
  `apply_member_change`), recomputes `last_message_*` on the chats they wrote in with
  `apply_message`'s photo rule, and returns their files (`{"avatars": [...], "chat-media":
  [...]}`). The function then deletes those with the service role. Rows first, so a failed
  delete changes nothing; files server side, because once the rows are gone the person can't
  read (so can't delete) their chat photos. Deploy:
  `supabase functions deploy delete-account --project-ref cfqlnthmqwkhjbhylvgu --use-api`; an
  unauthenticated POST must return 401. Logs: `"fn":"delete-account"`, counts only. Tested by
  the RLS suite's "deleted account" checks (rolled back). A live test deletes a real account:
  use a throwaway account, never a seed one (their messages are the demo chat) or David's.
- While a delete is on its way, its page hides Back and Settings holds Done and swipe-down;
  if the sheet is gone anyway when it finishes, YouView signs out at once. Leaving
  (Sign out or a deleted account) forgets the Instagram and Snapchat sign-ins in Ketchup
  (`AppModel.leave`). Offline previews never touch the real website data: `leave` and the
  web-chat rows skip it while previewing.
- "Sign out of Instagram/Snapchat in Ketchup" removes the `WKWebsiteDataStore.default()`
  records whose name matches that source's `domains`, then posts `webChatForgotten` and the
  open page goes back to its start URL. The first check after a fresh install can take a few
  seconds (WebKit starting); the row works meanwhile.
- Block is RLS: `messages_select_member` is `chat_id = any(my_chat_ids())` and
  `sender <> all(my_blocked_ids())`, each wrapped in `(select …)` so it's an InitPlan run once
  per query (keep that shape; a bare function call runs per row). `my_chats` leaves blocked
  senders out of unread counts and inbox lines. Its `me` and `blocked` CTEs stay
  `as materialized`: inlined, `auth.uid()` and `my_blocked_ids()` ran once per unread message
  (65 ms on the speed check's busy account, 2.2 ms materialized). `block_person` / `unblock_person` /
  `my_blocks()` are the only way in; a trigger drops the blocker's `ai_briefs` that could have
  read that person. `mark_read` is unchanged: the cursor is a time, and every count and
  catch-up window is read through the policy. In the app, `PeopleStore.block` also forgets
  the phone's kept thread copies (`DeviceStore.keepThreads([])`) and the catch-ups saved on
  the phone for every chat you share with them (`forgetAll(in:)`), and the open chat calls
  `ChatModel.blockChanged`. The RLS suite's "blocked:" checks cover it.
- Timing the read path (rolled back, as a seed member, here Maya): `set local role
  authenticated`, her jwt claims, then `explain (analyze, format json)` of
  `select … from messages where chat_id = '<breck>' order by created_at desc limit 200`
  seven times; take the median. Nov 3, 2026: 6.4 ms before 0007 part 2, 0.49 ms after.
- New reports (David, in the SQL editor; nobody can read them through the API):
  `select created_at, reason, reported_name, message_body, message_image, note, id from
  reports where reviewed_at is null order by created_at desc;` then
  `update reports set reviewed_at = now() where id = '<id>';` once looked at. Blocks:
  `select * from blocks;`.
- Report email: after a report the app calls `report-alert` (verify_jwt on), which emails
  `REPORTS_EMAIL` through Resend (reason, message or person, the SQL to read it; no names or
  text). It does nothing until David sets `RESEND_API_KEY` and `REPORTS_EMAIL` (optional
  `REPORTS_FROM`, default `Ketchup <noreply@vibetemp.com>`). Deploy:
  `supabase functions deploy report-alert --project-ref cfqlnthmqwkhjbhylvgu --use-api`; an
  unauthenticated POST must return 401. Logs: `"fn":"report-alert"`, counts only.
- Your people: `contacts` (owner-only select; writes through `add_contact`, which needs a
  shared chat, and `remove_contact`), `my_contacts()` by name, and `create_chat_with(name,
  people)`, which adds only your contacts and skips anyone who has blocked you (or whom you
  blocked) without saying so. `block_person` also removes the contact. New chat
  (`NewChatSheet(name:people:picked:)`) lists them; ChatsListView calls
  `KetchupAPI.createChat(name:with:)` when any are picked. No lookup by email or phone, by
  design. The RLS suite's last section covers it.
- Invite friends (`InviteView`, also `InviteSheet` from the inbox's +): a chat's code in
  `InviteMessage.text(for:)`; `InviteMessage.appLink` is nil until there's a TestFlight or
  App Store link. Text a friend presents `CNContactPickerViewController` (no permission)
  from the top view controller, then `MFMessageComposeViewController`; the simulator can't
  text, so it falls back to the share sheet. Tap-through needs a real phone.
- Previews: `-screen settings` (add `-section web`, `account` or `about`), `settings-sheet`
  (opened by the real You tab, `-KetchupOpenSettings`), `settings-name`, `settings-delete`,
  `settings-blocked`, `profile`, `profile-blocked`, `report`, `report-sent`, `info-blocked`,
  `chat-profile` and `chat-report` (the sheets opened from the thread), `people`,
  `people-empty`, `profile-contact`, `new-chat-people`, `invite`. The account email in
  previews is `david@example.com`.
- Settings' other rows: `profilePhotoSlot` (Photos) and `savedCatchUpsSlot` under "On this
  iPhone" (Speed). A section whose rows are all empty doesn't show.

## Photos (profile photos and photos in chats)
Code: `ios/Ketchup/Photos/` (`Avatar`, `AvatarCropper`, `ProfilePhotos` with
`.profilePhotoPicker(isPresented:)`, `ChatPhotos` with `PhotoUploads` and
`.chatPhotoPicker`, `PhotoBubble`, `PhotoViewer`, `RemoteImages`) and
`ios/Ketchup/Net/Storage.swift`. Migration `0006_photos.sql`, applied live in parts
(`0006_photos_1_avatars`, `0006_photos_2_chat_media`).
- `avatars` bucket: public (the app loads a photo by its public URL, no token), JPEG up to
  1 MB. On storage.objects you can insert, select and delete only in your own `<uid>/`
  folder, names `<uuid>.jpg`, 10 uploads an hour (`storage_uploads_ok`). No broad select
  policy, so nobody can list the bucket. `profiles.avatar_path` must be
  `<own id>/<uuid>.jpg` (check constraint); the app lowercases both ids to match.
- `chat-media` bucket: private, JPEG up to 5 MB. A photo message's files are
  `<chat>/<message id>.jpg` (at most 2048 px, 400 KB to 1.3 MB) and `<message id>_small.jpg`
  (768 px, 80 to 180 KB): the thread and Muse Spark use the small one, the viewer the
  full one. Members of the chat read (signed URLs) and upload (200 files an hour); only
  the uploader deletes. `messages.image_path`/`image_width`/`image_height`: the path must
  be in the message's own chat and already uploaded (the hygiene trigger checks), and the
  body may be empty with a photo. The inbox line says "📷 Photo" or "📷 " and the caption.
- Sending a photo: both copies go into the image cache under their final names first (the
  bubble shows at once), the small one uploads, then the full one, then the row goes in
  with the message's own id. A retry carries on from the file that didn't make it.
- Never delete storage files with SQL: it orphans the file (`storage.protect_delete`
  refuses anyway). The app deletes a replaced photo through the Storage API.
  Delete account removes a person's avatar and chat photos server side, after their rows
  (the `delete-account` edge function; see Settings and people).
- One image pipeline, `RemoteImages.shared`: decoded photos in memory at the drawn size,
  original bytes on disk in `Caches/photos` (150 MB, least recently used goes first),
  keyed `bucket/path`, emptied on sign-out. Paths never change, so nothing goes stale,
  and a private photo is signed only when it isn't on disk yet.
- Muse Spark sees photos (`_shared/photos.ts`): `catch-up` attaches the newest 6 photos among
  the messages it reads (catch-up: the unread ones; Ask: its 800-message window) as
  `image_url` parts with `data:` URLs of the small copies, downloaded with the caller's
  token (400 KB cap, 6 s timeout; a failure leaves the line `[photo]`). Transcript lines
  say `[photo N] caption`, each image is labelled `Photo N: [m12] from Maya`, and the
  header explains both (only when the window has photos). A 400 from Meta with photos
  attached retries once without them. The log line gains `photos` (how many attached).
  Measured Nov 3, 2026, on the 302-message demo chat with 2 made-up photos: about 640
  prompt tokens a photo, no added time (17.1 s to 16.0 s); the brief cited the door-code
  photo. `deno test supabase/functions/_shared/` must pass (12 tests since 0009). `_shared` changed,
  so after merge redeploy both `catch-up` and `catch-up-text`.
- Source chips: `RefContext.photo` returns a message's small copy, and `RefChip` draws it
  where the sender's dot goes (`ChatView.refContext` passes it).
- Settings has Add a photo (Change your photo once there is one) and Remove your photo,
  under You; `.profilePhotoPicker` is on `SettingsView`. The You tab's icon and header, and
  Settings' header, show your photo.
- Offline previews: `-screen photo-crop`, `photo-inbox`, `photo-chat`, `photo-info`,
  `photo-thread`, `photo-sending`, `photo-attach`, `photo-viewer`, `photo-catchup` (add
  `-section highlights`), `photo-answer`. The photos are drawn on the fly
  (`Debug/PreviewPhotos.swift`, no real people); Sam keeps his monogram to show the
  fallback. `photo-sending` sends Pickles the dog with a pretend 20 s upload; the brief and
  answer use Muse Spark's real words about the door-code photo.
- Checks: the RLS suite covers both parts (49/49 with Settings' checks, Nov 3, 2026). As anon, with the
  publishable key: `POST /storage/v1/object/list/avatars` returns `[]` and an upload
  returns 403. After real use: `select id, avatar_path from profiles where avatar_path is
  not null;`, `select bucket_id, count(*) from storage.objects group by 1;` and
  `select id, image_path, image_width, image_height from messages where image_path is not
  null order by created_at desc limit 5;`.

## Web-chat catch-up: Instagram and Snapchat (experimental, not released)
Code: `ios/Ketchup/WebChat/` is shared (`WebChatSource`, `WebChatBrowser`, `WebChatTab`,
`WebChatSheet`, `WebChatAPI`); `ios/Ketchup/Instagram/` and `ios/Ketchup/Snapchat/` hold each
site's reader and outline scripts and fixtures. The way in is the signed-in home's tab bar:
`HomeTab.all` in `Views/HomeTabs.swift` lists the tabs (Chats, Instagram, Snapchat, You), and
`.web(source)` hosts `WebChatTab(source:)`. Catch me up there is a small ketchup circle with the
drop on the right edge, above the site's message box (VoiceOver: "Catch me up"); it opens into
a "Reading the chat" pill while it reads. Edge function `catch-up-text`, migrations
`0004_text_brief_usage` and `0005_text_brief_snapchat`. README has the summary.
- The UI reuses `AI/` (CatchUpContent, SkimmingView, AIErrorCard, NotepadField, AnswerCard).
  `RefContext.hint` (default "Shows it in the chat") is the one seam: web chips show the whole
  message instead of jumping.
- App-bound domains: `ios/Ketchup-Info.plist` (merged with the generated keys, `INFOPLIST_FILE`)
  lists `WKAppBoundDomains`: Instagram's instagram.com, facebook.com, meta.com, fbsbx.com,
  fbcdn.net, cdninstagram.com, then Snapchat's snapchat.com, snap.com, sc-cdn.net, sc-static.net.
  That's the 10 allowed, so a new source needs room first. It's app-wide, and every web-chat
  web view is kept to it (`limitsNavigationsToAppBoundDomains`), so each source's `domains`
  must all be listed. Why both: Snapchat needs it for its service worker, and once the app
  lists any domains, Ketchup's scripts (`callAsyncJavaScript`) only run reliably in a web view
  kept to them. On Nov 3, 2026, with the list declared and Instagram's web view not kept to it,
  the Instagram reader failed on the real site ("Couldn't read this chat", Ketchup's message for
  any WebKit error during a read) while the sim's fixture still read fine; keeping it to the
  list fixed it. Test the real sites after any change here. Ketchup uses no message handlers
  or cookie APIs. The reader harness is its own macOS process, without this plist.
- Each source's web view (all use the default website data store):

  | | Instagram | Snapchat |
  |---|---|---|
  | Page | phone version | desktop (`preferredContentMode = .desktop`), laid out 1024 pt wide, scaled to fit (`WebChatWebView`, a view transform) |
  | User agent | WebKit's + `Version/26.0 Mobile/15E148 Safari/604.1` | `customUserAgent`, Mac Safari 27 |
  | `limitsNavigationsToAppBoundDomains` | true | true |
  | Thread pages | `instagram.com/direct/t/<id>` | `www.snapchat.com/web/<id>` |

- Snapchat, found Nov 3, 2026 (DEBUG trial, commits 0194b44 and c892873): a phone's user agent
  gets "use a computer"; desktop mode alone still lands on the mobile "Download Snapchat" page;
  desktop mode plus a wide layout gets the desktop page; signed in, the chat app then shows its
  own "Oops! Something went wrong" until the web view is app-bound. Nothing is injected.
  Sign in with username or email and password (no passkeys or Google in the app). On the
  shrunk page the first tap on a chat row can act as a hover; tap again. First real run
  (Nov 3, 2026, 3:14 AM, David's phone and account, a busy group chat): "Last 30" sent 30 of
  67 messages found, 0 loads, stop "enough", 16 ms of reading, about 10 s in all, attempt 0.
  "Last 120" (3:19 AM) sent exactly 120: found 145 after 2 loads of older messages, 1.1 s of
  reading, about 15 s in all. With both web views app-bound (3:33 AM): Instagram "Last 80" sent
  80 (found 82, 4 loads, 5.9 s of reading) and Snapchat "Last 80" sent 80 (found 106, 1 load,
  0.7 s). Not yet seen: a fresh sign-in in app-bound mode (David was signed in to both before).
  When a read fails, the DEBUG console says why with codes only: `[instagram] reader didn't
  run: WKErrorDomain <code>` or `[snapchat] reader said read_failed (<detail>)`.
- Adding a source: a `WebChatSource` (id is catch-up-text's `source`, also in `SOURCES` there and
  in the `text_brief_usage` source check, which needs a migration), a reader script that returns
  the same JSON, fixtures plus `.expected.json`, harness runs, and its domain in the plist.
- Rules: read only the chat the user has open, only on tap. Never inject scripts, read
  cookies or run anything on login pages. Store nothing on the server: no `ai_briefs` rows,
  and no message text, names or model output in logs (counts and token usage only). The
  catch-up and answers are kept on the phone only (SavedBriefs), until the user deletes them. Real tests use a separate
  test account with a staged chat where possible, and David signs in himself. DOM dumps or
  screenshots with real DMs stay in the session scratchpad, never in git or reports.
- Offline: `deno test supabase/functions/_shared/` (transcript format, index refs), then the
  readers against their synthetic fixtures (real WebKit, no network). Instagram:
  `swift scripts/ig-extractor-check/check.swift --html ios/Ketchup/Instagram/Fixture/ig-thread-fixture.html --js ios/Ketchup/Instagram/InstagramThreadReader.js --expected ios/Ketchup/Instagram/Fixture/ig-thread-fixture.expected.json`
  must print `PASS 88/88` (about 6 s; exit 1 = a mismatch, 2 = the reader failed). Then the
  same against `ig-thread-fixture-virtual.html` and its `.expected.json` (the real page's
  structure: column-reverse scroller, virtualized rows), once as is and once with
  `--url 'https://www.instagram.com/direct/t/ketchup-test-fixture/?anchoring=on'`; all three
  must pass 88/88. Snapchat (a computer-sized window):
  `swift scripts/ig-extractor-check/check.swift --html ios/Ketchup/Snapchat/Fixture/snap-thread-fixture.html --js ios/Ketchup/Snapchat/SnapchatThreadReader.js --expected ios/Ketchup/Snapchat/Fixture/snap-thread-fixture.expected.json --url https://www.snapchat.com/web/ketchup-test-fixture --size 1024x768 --args '{"maxMessages":300,"maxScrolls":8,"debug":true,"readerName":"David"}'`
  must print `PASS 62/62`. The Snapchat fixture is generated: change
  `scripts/ig-extractor-check/make_snap_fixture.py` and rerun it (both files at once). Change an
  Instagram fixture and its `.expected.json` together.
- Deploy: `supabase functions deploy catch-up-text --project-ref cfqlnthmqwkhjbhylvgu --use-api`,
  and redeploy `catch-up` after any `_shared` change. `list_edge_functions` → `verify_jwt: true`
  on both; an unauthenticated POST to each must return 401. The RLS suite covers the cap.
- Simulator, offline (no sign-in, no network, no Muse Spark): `-screen web-instagram` and
  `-screen web-snapchat` (each page on its synthetic thread), `web-intro`, `web-reading`,
  `web-brief`, `web-error`, `web-quote`; `home-instagram` and `home-snapchat` show the page as
  a tab. `-KetchupSnapchatFixture NO` (or Instagram) keeps the real site in a preview.
  Signed in: tap the Instagram or Snapchat tab → `…` → Testing → a test thread → the ketchup
  drop (Catch me up); `-KetchupInstagramFixture YES` (or Snapchat) opens the
  synthetic thread instead of the real site. The console prints counts only:
  `[snapchat] read N messages, …`, and each page as host and path with ids left out. Tap the
  menu once and wait: a second tap where the button was lands on "Until I stop scrolling".
- **Until I stop scrolling** (Nov 4, 2026; Android's `ThreadReader.follow` on iPhone). Menu item
  under Last 120; `WebChatBrowser.follow` and `WebFollow` (`WebChat/WebChatFollow.swift`),
  `FollowingPanel` in `WebChatTab.swift`. It never scrolls: every 250 ms the app runs the
  reader with `follow` = "start", then "look", and at the end "finish" (same JSON as Last N)
  or "stop". Only what has been on screen counts. The reader keeps what it read in the
  `.defaultClient` world's own `globalThis.ketchupFollow`, deleted on finish or stop, and sets
  no timers or listeners. Instagram lines rows up by place from the list's bottom (as Last N
  does, allowing for anything new at the bottom), Snapchat lays each read over the last one.
  Done at the first of: 3 s after the last new message, 5 s after the start with none, 600
  messages or 3 minutes (`stop` "budget"; the rest "enough"), or Catch me up now. Stop, another
  tab, the app going to the background, another page or thread: nothing sent, nothing kept.
  Its log line: `[instagram] follow read N messages, L looks, stop enough (quiet), gaps G,
  dupes D, X ms`; `gaps` counts rows Instagram never filled in while on screen (the view
  jumped past them), which follow can't go back for.
  Offline checks (no sign-in, no network), each must print the counts shown (Nov 4, 2026):
  - Harness, same commands as above plus `--follow` (a pretend person scrolls the page from a
    third content world: `--person 'up 8, down 2, up 120'` by default) and without
    `maxMessages`: Instagram `PASS 88/88` (88 read, 58 looks), the virtual one `PASS 88/88`,
    Snapchat `PASS 62/62`; each also says the scroll moved during 0 looks, nothing was left
    in the page after finish or after stop, and another thread mid-follow gave
    `thread_changed`. The virtual one with `?anchoring=on` reads 69 of 88: the view jumps past
    part of each older batch. `--person 'up 0'` finishes at about 5 s with what's on screen.
  - Simulator: `-screen web-instagram -followTest YES` (add `-webFixture
    ig-thread-fixture-virtual` for the other Instagram thread) and `-screen web-snapchat
    -followTest YES`, with `--console-pty`: `follow check: 88 of 88 match the test thread's
    newest 88 in order, 88 of its 88 read, 0 repeated or not in it` (62 for Snapchat). The
    pretend person scrolls back down twice midway. `-readTest 10` (or 30) checks a Last N read
    the same way: `Last 10 check: 10 of 10 match …`.
  - Previews: `web-following` and `web-following-snapchat` run the real follow held open (no
    timers) for screenshots; swipe the page and the count goes up. Then the sheet stops at
    the server call (offline).
- On David's phone: `xcrun devicectl list devices` for the udid, build with
  `-destination 'id=<udid>'` (or `generic/platform=iOS` while it's locked) and
  `-allowProvisioningUpdates`, then
  `xcrun devicectl device install app --device <udid> <DerivedData>/Build/Products/Debug-iphoneos/Ketchup.app`
  (`<DerivedData>` is the folder whose `info.plist` `WorkspacePath` is this checkout: each worktree
  session builds into its own `Ketchup-*` folder, so the newest one may not be main's;
  `/usr/libexec/PlistBuddy -c 'Print :WorkspacePath' <folder>/info.plist`)
  (it fails while the phone is locked). To open a screen there:
  `xcrun devicectl device process launch --device <udid> --terminate-existing --console com.vibetemp.ketchup -- -screen web-snapchat -KetchupSnapchatFixture NO`
  (app arguments go after `--`). Instagram real runs (Nov 3, 2026, David's account): before the
  virtualization fix about 31 messages with every sender shown as the group's name; after it,
  real names, and "Last 120" returns exactly 120 (found 122, stop "enough", 6 loads, 56 steps,
  9 s of reading). The log line's `reader` object explains a short count: `stop` says why it
  ended, `units` vs `found` shows pieces that weren't messages, `dupes` shows rows read twice.
  Replies carry their quote (Instagram draws it without `dir="auto"`, in a half-faded line with
  a 4px bar). The DEBUG "Save page outline (no text)" writes `tmp/<source>-outline.txt`; pull it
  with `xcrun devicectl device copy from --device <udid> --domain-type appDataContainer --domain-identifier com.vibetemp.ketchup --source tmp/snapchat-outline.txt --destination <scratchpad file>`.
- Live check: `query_logs`, source `function_logs`, lines with `"fn":"catch-up-text"` carry
  `{source, mode, attempt, messages, prompt, completion, reasoning, reader}` and nothing else.
  Usage: `select source, mode, message_count, created_at from text_brief_usage order by created_at desc limit 5`.

## Android (`android/`, started Nov 3, 2026)
Kotlin and Compose port of the app, plus an accessibility service that reads the open Instagram or
Snapchat DM thread for `catch-up-text`. `android/README.md` is the recipe: build with Android Studio's
JBR as `JAVA_HOME` and `ANDROID_HOME=~/Library/Android/sdk`, `./gradlew :app:assembleDebug
:app:testDebugUnitTest` (zero Kotlin warnings), AVDs `ketchup_chat`, `ketchup_brief`, `ketchup_reader`,
offline previews with `adb shell am start -n com.vibetemp.ketchup/.MainActivity --es screen <name>`.
It also has who owns which files (chat, brief, reader slices) and the frozen `data/BriefSource.kt` contract.

**David's test phone** (moto g 2025, Android 16) connects over Wi-Fi debugging, no cable: once he turns
on Developer options → Wireless debugging (paired with this Mac through Android Studio), `adb mdns
services` lists it and `adb connect <ip:port>` (or adb's auto-connect) attaches it. It drops when the
phone sleeps, so a background loop that waits for it, then installs, works well. Read only Ketchup's
own log tags: `KetchupReader` (read counts, and why no thread was found), `KetchupReaderDump` (layout:
view ids, bounds, text lengths, never text) and `KetchupNet` (network failures). Never take a
screenshot or a `uiautomator dump` while Instagram or Snapchat is open (both include message text),
and never turn the accessibility service on over adb on his phone; he turns it on himself.
