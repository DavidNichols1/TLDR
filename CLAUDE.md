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
- Deploy the edge function without Docker:
  `supabase functions deploy catch-up --project-ref cfqlnthmqwkhjbhylvgu --use-api`
  (verify_jwt stays on). Check with `list_edge_functions` → `verify_jwt: true`, and an
  unauthenticated POST must return 401.
- Muse Spark: `supabase/functions/_shared/muse.ts`, `POST https://api.meta.ai/v1/chat/completions`,
  model `muse-spark-1.3` (override with `META_MODEL`), docs at https://dev.meta.ai/docs.
- Logs for a catch-up call: Supabase MCP `query_logs`, source `function_logs`; each Muse call
  logs `{mode, attempt, messages, prompt, completion, reasoning}` token counts. Latency is in
  `ai_briefs.latency_ms`. Keep `META_REASONING=low` (minimal invented a plan time on Nov 2).
- The app prefetches a catch-up when a chat opens with 15+ unread (ChatModel.open); the read
  cursor moves only when the user opens the result.
- Check secrets by name only: `supabase secrets list --project-ref cfqlnthmqwkhjbhylvgu`
  (run it from the repo root; it writes a `supabase/.temp` cache that is gitignored there).
- `enforce_message_hygiene` forces `messages.created_at = now()` on insert; the seed
  backdates with an update afterwards.

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

## Demo seed
`scripts/seed-demo/README.md`. 302-message "Breck Weekend 🎿" chat from 5 test accounts;
the viewer sets display name **David**, joins with the printed invite code, and has
302 unread. `--rearm` resets David to all-unread between video takes.

## Web-chat catch-up: Instagram and Snapchat (experimental, not released)
Code: `ios/Ketchup/WebChat/` is shared (`WebChatSource`, `WebChatBrowser`, `WebChatTab`,
`WebChatSheet`, `WebChatAPI`); `ios/Ketchup/Instagram/` and `ios/Ketchup/Snapchat/` hold each
site's reader and outline scripts and fixtures. `Instagram/InstagramEntry.swift` is the inbox's
camera button (a menu of the sources, each `WebChatTab(source:)` full screen) until the home
becomes a pager with a page per source. Edge function `catch-up-text`, migrations
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
  cookies or run anything on login pages. Store nothing: no `ai_briefs` rows, and no message
  text, names or model output in logs (counts and token usage only). Real tests use a separate
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
  `web-brief`, `web-error`, `web-quote`. `-KetchupSnapchatFixture NO` (or Instagram) keeps the
  real site in a preview. Signed in: the inbox camera button (later the pager page) → a source →
  `…` → Testing → a test thread → Catch me up. The console prints counts only:
  `[snapchat] read N messages, …`, and each page as host and path with ids left out. Tap the
  menu once and wait: a second tap where the button was lands on "Last 120".
- On David's phone: `xcrun devicectl list devices` for the udid, build with
  `-destination 'id=<udid>'` (or `generic/platform=iOS` while it's locked) and
  `-allowProvisioningUpdates`, then
  `xcrun devicectl device install app --device <udid> <DerivedData>/Build/Products/Debug-iphoneos/Ketchup.app`
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
