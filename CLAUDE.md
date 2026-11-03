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
  retries the first page every 4 s, whether or not Realtime is live.
- `Profile`, `ChatSummary`, `Member` and `Message` are `Codable` for this: new fields are kept
  automatically and must be Codable too.
- Offline check, no sign-in: `-screen store-check` must show "11 of 11 passed, 1 skipped" on a
  simulator (data protection only exists on a phone, where it's 12 of 12); the console prints
  `[store-check] PASS …`. DEBUG builds log reads as `[store] read a thread, 74 KB in 0.9 ms`.
- The files on a simulator: `xcrun simctl get_app_container <udid> com.vibetemp.ketchup data`,
  then `Library/Application Support/Ketchup/`.
- Previews: `inbox-loading`, `chat-loading`, `ai-loading-blank` (skeletons; `-reduceMotion YES`
  holds them still), and `chat-kept` (a live ChatModel opening on a kept copy with no server, in
  a scratch folder, never the real one). Screenshots: `docs/screens/speed/`.

## Demo seed
`scripts/seed-demo/README.md`. 302-message "Breck Weekend 🎿" chat from 5 test accounts;
the viewer sets display name **David**, joins with the printed invite code, and has
302 unread. `--rearm` resets David to all-unread between video takes.

## Settings and people (migration 0007)
Code: `ios/Ketchup/People/` (`SettingsView`, `AccountPages`, `SettingsPieces`, `Account.swift`),
`Net/PeopleAPI.swift`, `WebChat/WebChatSignOut.swift`. Settings opens from the inbox's top-left
photo (your initial until you add one) as a sheet; signing out waits for the sheet to close (`SettingsExit`, the sheet's
`onDismiss` in `ChatsListView`), so it can't be left over sign-in.
- `0007_people.sql` is one file applied live in parts, one `apply_migration` per slice, each
  named `0007_people_<part>` (so far `0007_people_account`, `0007_people_account_photos`).
  Append, never rewrite: a fresh project runs the whole file once.
- `delete_account()` (security definer, `authenticated` only): deletes friends' saved
  catch-ups that read the caller's messages, then the auth user (profile, memberships,
  messages, own briefs cascade; a chat they were last in goes through `apply_member_change`),
  then recomputes `last_message_*` on the chats they wrote in, with `apply_message`'s photo
  rule ("📷 Photo"). Tested only by the RLS suite's "deleted account" checks (rolled back). A
  live test deletes a real account: use a throwaway account, never a seed one. SQL can't
  delete Storage files, so `AppModel.deleteAccount()` (People/Account.swift) calls
  `ChatPhotos.deleteMine()` first.
- "Sign out of Instagram/Snapchat in Ketchup" removes the `WKWebsiteDataStore.default()`
  records whose name matches that source's `domains`, then posts `webChatForgotten` and the
  open page goes back to its start URL. The first check after a fresh install can take a few
  seconds (WebKit starting); the row works meanwhile.
- Previews: `-screen settings` (add `-section web`, `account` or `about`), `settings-sheet`
  (opened by the real inbox, `-KetchupOpenSettings`), `settings-name`, `settings-delete`.
  The account email in previews is `david@example.com`.
- Rows still to come are marked `SLOT` in `SettingsView.swift`: Blocked people (People,
  slice 2), and Saved catch-ups and Clear cache under "On this iPhone" (Speed). A section
  whose rows are all empty doesn't show.

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
  `ChatPhotos.deleteMine(app:)` deletes someone's avatar and every chat photo they sent,
  for Delete account (call it before `delete_account()`).
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
  photo. `deno test supabase/functions/_shared/` must pass (6 tests). `_shared` changed,
  so after merge redeploy both `catch-up` and `catch-up-text`.
- Source chips: `RefContext.photo` returns a message's small copy, and `RefChip` draws it
  where the sender's dot goes (`ChatView.refContext` passes it).
- Settings has Add a photo (Change your photo once there is one) and Remove your photo,
  under You; `.profilePhotoPicker` is on `SettingsView`. The inbox's top-left button and
  Settings' header show your photo.
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
site's reader and outline scripts and fixtures. The way in is the signed-in home's pager:
`HomePage.all` in `Views/HomePager.swift` lists the pages (Chats, Instagram, Snapchat), and
`.web(source)` hosts `WebChatTab(source:)`. Edge function `catch-up-text`, migrations
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
  `web-brief`, `web-error`, `web-quote`; `home-instagram` and `home-snapchat` show the page in
  the pager. `-KetchupSnapchatFixture NO` (or Instagram) keeps the real site in a preview.
  Signed in: swipe to the Instagram or Snapchat page (or tap its name at the top) → `…` →
  Testing → a test thread → Catch me up; `-KetchupInstagramFixture YES` (or Snapchat) opens the
  synthetic thread instead of the real site. The console prints counts only:
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
