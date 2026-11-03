# Ketchup for Android

The same app as iOS (`ios/`), in Kotlin and Jetpack Compose, on the same Supabase project. Plus one thing iOS can't do: an accessibility service that reads the DM thread you have open in the official Instagram or Snapchat app, when you ask, and sends it to the `catch-up-text` edge function for a Muse Spark catch-up.

The foundation (Nov 3, 2026) is the Gradle project, the diner theme, the data layer and the contracts below. Three slices build on it: chat, brief and reader.

## Build and run

```bash
cd android
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
export ANDROID_HOME="$HOME/Library/Android/sdk"   # a fresh worktree has no local.properties
./gradlew :app:assembleDebug :app:testDebugUnitTest
```

- Same Gradle (9.4.1), AGP (9.2.1), Kotlin (2.2.10) and Compose BOM (2026.02.01) as AurariaGO's Android app, so it builds on David's Mac. kotlinx.serialization 1.9.0 for JSON.
- compileSdk is API 36 (its 36.1 revision, the platform installed on the Mac), targetSdk 36, minSdk 26.
- **Zero Kotlin warnings.** Check with `./gradlew ... --console=plain 2>&1 | grep -c '^w: '`.
- The unit tests run on the JVM with a fake transport: no network, no live backend.

Emulators, one per slice so they can run at once (Pixel 7, `system-images;android-36;google_apis;arm64-v8a`): `ketchup_chat`, `ketchup_brief`, `ketchup_reader`.

```bash
~/Library/Android/sdk/emulator/emulator -avd ketchup_chat -no-snapshot-save &
ADB=~/Library/Android/sdk/platform-tools/adb
$ADB devices                                   # pass -s emulator-55xx when several run
$ADB install -r app/build/outputs/apk/debug/app-debug.apk
$ADB exec-out screencap -p > <scratch folder>/shot.png   # never into the repo
```

## Offline previews (debug builds)

```bash
adb shell am start -n com.vibetemp.ketchup/.MainActivity --es screen <name>
```

opens one screen on fixture data: no sign-in, no network, no Muse Spark. While a preview is open the client refuses to send anything (`Previewing.active`). `list`, or a name that isn't a screen, shows every name; tap one to open it. Release builds ignore the extra (`src/release/.../debug/PreviewHost.kt`).

| Name | File | Shows |
|---|---|---|
| `design` | `debug/DesignPreviews.kt` (shared) | The drop, wordmark, buttons, monograms, paper, colors |
| `signin`, `signin-code`, `name`, `home`, `home-instagram`, `home-snapchat`, `inbox-loading`, `inbox-empty`, `new-chat`, `join`, `chat`, `chat-loading`, `chat-jump`, `chat-joined`, `chat-not-sent`, `info`, `settings` | `debug/ChatPreviews.kt` | The chat slice, under iOS's `-screen` names: sign-in and its code step (countdown running), the name step, the pager on each page, the inbox (full, skeleton, empty) and its New chat and Join sheets, the Breck chat (302 new; `chat-jump` stages a brief's jump to Maya's "$540 total"; `chat-joined` has Rowan, made up, join and say hi: "Rowan joined" under "1 new"), Members and invite, Settings. `chat-not-sent` shows a send that failed. `chat-breck` is the old name for `chat`. Sends in a preview settle after 400 ms and never leave the phone |
| `brief`, `brief-plans`, `brief-owes`, `brief-questions`, `brief-checked`, `brief-cached`, `brief-loading`, `brief-loading-still`, `brief-empty`, `brief-error`, `brief-signed-out`, `brief-gone`, `brief-thread`, `brief-thread-loading`, `brief-citations`, `brief-own-task`, `ask-first`, `ask`, `ask-answer`, `ask-notfound` | `debug/BriefPreviews.kt` | Catch me up and Ask on Muse Spark's real Breck brief and answers, and iOS's hand-written brief of the Instagram thread. A scripted backend plays them back: Try again re-reads, Ask answers after a pause ("hot tub" gets the one the chat doesn't say). `-still` is the Reduce Motion skim; `ask-first` is the page the chat's Ask button opens; `brief-own-task` opens the real `BriefActivity` the way the reader service will |
| `reader-instagram` | `debug/ReaderPreviews.kt` | The synthetic Instagram thread as catch-up-text will see it; "Open the brief" hands it to `BriefActivity` |

Fixtures are debug-only assets in `app/src/debug/assets/fixtures/`: iOS's `messages.json`, `brief.json`, `ask.json`, `ask-notfound.json`, and `instagram-thread.json` (iOS's synthetic Instagram fixture as a `TextThread`, made-up people). `debug/PreviewData.kt` decodes them with the app's own JSON setup; in a composable, `val data = previewData()`.

## Who owns what

| Slice | Owns |
|---|---|
| Chat | `ui/auth/`, `ui/chats/`, `ui/chat/`, `data/realtime/`, the nav graph and `MainActivity`, `debug/ChatPreviews.kt`, `strings.xml` |
| Brief | `ui/brief/`, `debug/BriefPreviews.kt`, `brief_strings.xml` |
| Reader | `reader/`, `res/xml/reader_service.xml`, `debug/ReaderPreviews.kt`, `reader_strings.xml` |

Everything else is shared: the theme (`ui/theme/`, `ui/design/`), `data/` except `data/realtime/`, `AndroidManifest.xml`, the Gradle files, and the rest of `debug/` (`PreviewHost.kt`, `PreviewData.kt`, `DesignPreviews.kt`, the fixtures). A slice that needs a change there keeps it small and says so in its report. New files are fine anywhere a slice owns; a new drawable or other resource file takes the slice's prefix (`chat_`, `brief_`, `reader_`). Paths are under `app/src/main/java/com/vibetemp/ketchup/` (previews under `app/src/debug/java/...`).

## Contracts

**`data/BriefSource.kt` is frozen.** A brief is for a `BriefSource`: either `BriefSource.Chat(id, name)`, a Ketchup chat, or a `TextThread` read off another app.

- `TextThread(source, title, messages, stats?)`: `source` is `TextSource.INSTAGRAM` or `SNAPCHAT` (catch-up-text's `source`), `title` its `thread_title`, messages oldest first.
- `TextMessage(sender, text, isMine, quote?, at?)`, with `Quote(sender?, text?, isMine)` for a reply. On the wire it becomes catch-up-text's `{sender, text, at?}`: the reader's own messages go under their Ketchup name (`wireSender`), and a reply leads with its quote, `(replying to Maya: "...") text`, exactly like the iOS readers (`wireText`; a unit test checks all 88 messages of the iOS fixture).
- `ReaderStats`: counts only, for catch-up-text's log.
- catch-up-text cites messages by their index; `thread.message(ref)` turns a ref back into its message. Every `refs` list is `List<String>`: message ids for Ketchup chats, "0", "12" for a thread.
- A thread is never written to disk or logged; it's held in memory for one catch-up.

**Starting the brief** (brief slice owns the activity; these two functions are what the others call):

```kotlin
BriefActivity.start(context, source)            // from the reader service it adds FLAG_ACTIVITY_NEW_TASK
BriefActivity.intent(context, source): Intent
BriefActivity.askIntent(context, source): Intent // the chat's Ask button: opens on Ask, no catch-up
```

A chat rides in the Intent's extras; a thread stays in this process's memory with only a key in the Intent (Binder's size limit, and a friend's messages shouldn't sit in the system's copy). `BriefSourceIntent.from(intent)` reads it back, or null after the process died. `BriefActivity` has its own task affinity, so over Instagram, Back returns to Instagram.

What the brief does with it (`ui/brief/`): the catch-up starts as the page opens (a ViewModel keeps it through a rotation), with the skim of the real messages while Muse Spark reads, and Ask the chat sits under the brief on the same page. Opened with `askIntent`, it's iOS's Ask sheet instead: Ask the chat on its own, field focused, no catch-up call; Catch me up in the top bar runs one, and the brief arrives above Ask.

- **A Ketchup chat**: a tapped source finishes with `RESULT_OK` and `EXTRA_JUMP_TO_MESSAGE` (the message id). Like iOS, a brief that lands moves the read cursor to its `until`, so refresh the chat's unread count when the brief returns. A finished brief survives the process dying in the background (saved state, chats only).
- **A thread**: a tapped source opens the item's cited messages in a sheet (`thread.message(ref)`), since there's no chat in Ketchup to jump into. `reader_name` is the reader's Ketchup display name, or "Me" without one, like iOS. Nothing from the thread is kept.

**The API** (`data/KetchupApi.kt`, `KetchupApi.get(context)`, safe from the service too). Every call throws `ApiException` with a sentence a person can read.

```kotlin
suspend fun sendCode(email: String)
suspend fun verifyCode(email: String, code: String): AuthSession
suspend fun signOut()
val session: StateFlow<AuthSession?>
suspend fun myProfile(): Profile?
suspend fun setDisplayName(name: String)
suspend fun myChats(): List<ChatSummary>
suspend fun createChat(name: String): String
suspend fun joinChat(code: String): String?
suspend fun leaveChat(chatId: String)
suspend fun markRead(chatId: String, at: Instant? = null)
suspend fun members(chatId: String): List<Member>
suspend fun messages(chatId: String, before: Instant? = null, limit: Int = 200): List<Message>   // oldest first
suspend fun messagesAfter(chatId: String, after: Instant): List<Message>
suspend fun send(chatId: String, body: String, id: String = UUID.randomUUID().toString()): Message
suspend fun catchUp(chatId: String, timeZone: String = ...): CatchUpResponse
suspend fun ask(chatId: String, question: String, timeZone: String = ...): AskResponse
suspend fun catchUp(thread: TextThread, readerName: String, timeZone: String = ...): CatchUpResponse
suspend fun ask(thread: TextThread, question: String, readerName: String, timeZone: String = ...): AskResponse
suspend fun catchUp(source: BriefSource, readerName: String): CatchUpResponse
suspend fun ask(source: BriefSource, question: String, readerName: String): AskResponse
```

`CatchUpResponse` and `AskResponse` are `BriefResponse<CatchUp>` and `BriefResponse<ChatAnswer>`, the envelope both functions return (`empty`, `cached`, `brief_id`, `until`, `message_count`, `latency_ms`, and `source`/`truncated` from catch-up-text). Lower level, `KetchupApi.get(context).client` has `select`, `insert`, `rpc`, `function` and `rest`. Realtime is the chat slice's: it takes `client.freshAccessToken()` and `Config.REALTIME_URL`.

- The session lives in private app storage (`ketchup.session` shared preferences); the manifest keeps the app out of backups and device transfers. Only Supabase Auth refusing the refresh token (400/401) signs you out.
- Times are `java.time.Instant` and keep Postgres's microseconds, so a read cursor set to a message's own time covers it.

## The reader (experimental, sideloaded only)

`reader/KetchupReaderService` reads the DM thread open in the official Instagram or Snapchat app, when the person taps, and hands a `TextThread` to `BriefActivity.start`. Like the iOS web readers it's against both apps' terms and Google Play wouldn't allow it, so it stays experimental and sideloaded.

- **Spotting a thread** (no tap needed, no text read): a structure-only copy of the screen (`NodeSnapshots.structure`: class names, bounds, flags, text lengths, and an editable field's hint) must show a message list over a "Message..." composer ("Send a chat" on Snapchat), `ThreadLayout`. Then a 56 dp Ketchup bubble floats over it (`ReaderOverlay`, `TYPE_ACCESSIBILITY_OVERLAY`, no draw-over-apps permission), draggable, kept above the composer, gone when the thread is.
- **Reading** (only after a tap): the bubble opens a panel, Last 10 / 30 / 80 / 120 two by two, and Until I stop scrolling under them (`ReaderPanel`). Not signed in, or no consent yet: it says so and opens Ketchup. The read (`ThreadReader`) scrolls back with `ACTION_SCROLL_BACKWARD`, waits for the list to settle, copies the screen with text, and lays the pages together by the shift the shared pieces agree on (`Stitcher`), so nothing is read twice or lost. It stops for the iOS readers' reasons (`enough`, `start`, `loads`, `steps`, `budget`, `no-scroller`), puts the thread back, and hands over the newest N with `ReaderStats` (counts only). Stop puts it back and hands nothing over.
- **Until I stop scrolling** (`ThreadReader.follow`): no scrolling of its own. It reads what's on screen, then what the person scrolls past (each look waits for the list to stand still: read mid-scroll, the accessibility cache can still hold a recycled row's old content), laid together by `Stitcher.addFollowing` with the same dedupe. A page that moved back down is left out (read on the way up, or flung past), and a page more than a page away is either something already read (left out) or new and older (placed above, and the walk forgets whose run it was across the unread stretch). It finishes 3 s after the last new message, 5 s after starting if none turned up, at 600 messages or after 3 minutes; Catch me up now finishes at once, Stop hands over nothing. Stats say `stop: enough` (or `budget` at 3 minutes). On the fixture (Nov 3, 2026): slow scrolling read 24, fast flings with a scroll back down read 25, each in the fixture's order and once.
- **Parsing** (`PageParser`, `ThreadWalk`, pure Kotlin behind `ReaderNode`, JVM-tested): never by view ids, which Instagram obfuscates. Right of center is mine; a long-pressable box that isn't the full width is a bubble; a short loose line over their bubble names the run in a group; "You replied to Maya" plus the next bubble in the row makes a `TextMessage.Quote`; photos, videos, voice notes, GIFs, stickers and shared posts become "[photo]" style placeholders; centered times ("Today 3:41 PM", `Stamps`) give `at`; notices, "Seen", reactions and avatars are dropped. A 1:1 thread names them after its title.
- **Privacy:** nothing is stored (a consent flag aside); logs are counts only (`adb logcat -s KetchupReader`).
- **Snapchat** (`SnapchatRows`, `SnapchatWalk`, from a structure dump of the real app on Nov 3, 2026): Snapchat keeps a few view ids readable, so its thread is spotted by the composer `chat_input_text_field` and the list `chat_message_list` (its hint and the shape rules are the fallback; Instagram's rules are unchanged). Every message sits on the left, so the sender is the last run header above it (the name with a time beside it). A header saying "ME" or the person's name on Snapchat (case and extra spaces aside) is theirs; nothing else is. The first time the Snapchat bubble is tapped with no name saved, it opens "Your name on Snapchat" (`SnapchatNameActivity`, prefilled with the Ketchup name; Save goes back to Snapchat with the panel open), and the Snapchat page shows it with Change. The name (`ReaderMemory`) is the only thing the reader keeps: private app storage, never sent, forgotten on sign-out (`AppModel.signOut`). A list that says it scrolled but didn't move reads as nothing new, not as a fresh page (`Stitcher`). A `QuotedMessageView` (quoted sender, time, quoted text) becomes the reply's `Quote`; reactions (`chat_reactions/...` and their count), notices and rows bound above the screen (hidden) are skipped; a centered or capitalized date row ("TODAY") dates the runs under it. Debug builds log why a watched app's screen isn't a thread, with view ids and hint lengths only: `no thread on snapchat: no composer (<view id> h=<hint length>)` or `no list (composer <view id>; scrollers: ...)`.
- **The page** (`ReaderPage(source)`, the pager's Instagram and Snapchat pages): what the bubble does, whether it's on (checked on resume), Turn on (the consent screen, then `Settings.ACTION_ACCESSIBILITY_SETTINGS`), the Android 13+ "Allow restricted settings" tip for sideloaded installs, and Open Instagram (or a note that it isn't installed). Snapchat's page says it hasn't been tested on a real phone.
- **Previews** (`debug/ReaderPreviews.kt`, besides `reader-instagram` in the table above): `reader-instagram-page` and `reader-snapchat-page` (the live pages: is the bubble on, is the app installed), `reader-page-on`, `reader-consent`, `reader-panel` (the bubble and each panel state: pick, reading, sign in, set up, nothing found) and `reader-fixture` (opens the fixture thread below).

Check it on the `ketchup_reader` emulator (no Instagram there; debug builds draw a synthetic thread with made-up people, `debug/ReaderFixtureActivity`, and a debug service config adds the app's own package so only that screen counts as a thread):

```bash
ADB="$HOME/Library/Android/sdk/platform-tools/adb -s emulator-5564"
$ADB shell settings put secure enabled_accessibility_services com.vibetemp.ketchup/com.vibetemp.ketchup.reader.KetchupReaderService
$ADB shell settings put secure accessibility_enabled 1      # a force-stop of the app turns it off again
$ADB shell am start -n com.vibetemp.ketchup/.MainActivity --es screen reader-consent   # agree once, or tap through reader-instagram-page
$ADB shell am start -n com.vibetemp.ketchup/.debug.ReaderFixtureActivity               # the bubble shows; tap it, pick Last 30
$ADB logcat -s KetchupReader    # "read instagram: 30 kept, found 38, ... stop enough" and "fixture check: 30 of 30 match"
```

The fixture is offline (no account needed, nothing sent); `--ez live true` keeps the sign-in check, so a signed-out phone shows "Sign in to Ketchup first". On Nov 3, 2026: Last 30 read 30 of 30 in 2.2 s, Last 120 read all 88 (stop `start`) in 10.3 s, both matching the fixture.

**Tuning on a real phone** (David signs in himself; real DMs stay off git, screenshots and reports): open a thread, then long-press the bubble, or `$ADB shell am broadcast -a com.vibetemp.ketchup.debug.READER_DUMP -p com.vibetemp.ketchup` and `$ADB logcat -s KetchupReaderDump`. Debug builds log the screen's structure: class names, view ids, bounds, flags and text lengths, never text. The first things to check there: that Instagram's bubbles are long-pressable (the parser's bubble rule) and that its list advertises scroll-back. On Snapchat, check that its own runs say "ME" (or your Ketchup name) and that a reply keeps its quote.

## The design system

`ui/theme/`: `KetchupTheme { }` wraps a screen; `KetchupTheme.colors` (cream, card, rule, ink, inkSoft, inkFaint, onInk, ketchup, ketchupText, onKetchup, mustard, onMustard, pickle, people), `KetchupTheme.type` (serif, mono and sans styles in sp, after iOS's text styles), `KetchupTheme.reduceMotion`, `Motion`. Values match iOS `Theme.swift`; `colors.person(name)` uses iOS's hash, so Maya is the same teal on both phones. Android's built-in serif and monospace stand in for New York and SF Mono.

`ui/design/`: `Modifier.paperCard()`, `Kicker`, `SectionTitle`, `Wordmark`, `KetchupDrop` and `KetchupDropShape`, `CapsuleButton` (`ButtonFill.Ketchup`, `Ink`, `Outline`; `compact`), `Modifier.pressable { }`, `Monogram`. `docs/DESIGN.md` has the rules: one ketchup thing per screen, mustard only for what's yours, no gradients or shadows, never em dashes.

## The chat slice

`ui/auth/` (sign-in, the name step, form pieces), `ui/chats/` (`AppModel`, the nav graph in `KetchupRoot.kt`, the pager, the inbox, New chat and Join, Settings), `ui/chat/` (`ChatModel`, the thread, the composer, the Catch me up bar, Members & invite).

"Maya joined" lines (migration 0009): `Message.kind` is `"text"` or `"joined"` (a row without one, from before 0009, reads as text) and messages are read with `select=*`, so the app works on either side of the migration. `threadRows` draws a join as `ThreadRow.Joined` (`JoinedLine`: small, centered, the name in its person color, "You joined" in ink), ends a run with it, and shows only each person's newest. `ChatModel` never counts one as unread, though the "N new" line goes above it when it's after your cursor.

- **Realtime** (`data/realtime/`) is a small hand-rolled WebSocket client (RFC 6455 over the system's TLS, no new dependency) speaking the Phoenix frames iOS `Net/Realtime.swift` sends: one socket per open chat, `realtime:chat-<id>` with the postgres_changes INSERT filter and the member's token, a heartbeat every 25 s, `access_token` when the token refreshes, iOS's backoff. The chat polls every 4 s while it isn't live, and only while the app is on screen.
- **`ChatModel`** ports iOS's: the first page reaches back past the unread part, your cursor comes from your member row, pages and Realtime rows merge by id, sends are optimistic under the row's own id. The read-cursor rules are at the top of the file.
- **The brief**: Catch me up opens `BriefActivity.intent(context, BriefSource.Chat(id, name))` and Ask opens `BriefActivity.askIntent(...)` (Ask first, no catch-up); on the way back the chat re-reads your cursor (a catch-up moves it) and jumps to `EXTRA_JUMP_TO_MESSAGE` if there is one.
- **Not ported yet**: photos, the copy kept on the phone, saved catch-ups, profiles, block and report, your people, invite friends.

## Plans (migration 0010)

Android has no purchases (it's sideloaded, so Play Billing doesn't apply); plans are bought on the iPhone and the server's limits apply to both. Two things here:

- **The one-time Muse Spark question.** `data/ConsentGate.kt` (shared data layer) runs before `catch-up` and `catch-up-text` through `SupabaseClient.function()` (one marked line). Once per account it checks `ai_consents`; with no row, `ui/plans/ConsentDialog.kt` asks, in iOS's words, what goes to Meta's Muse Spark (friends' messages included), that Meta doesn't train on it, and an explicit "I'm 18 or older" before Allow works. Yes saves the row, then the brief goes; Not now sends nothing ("Nothing was sent to Muse Spark."). `BriefActivity`, where every brief starts (a chat's Catch me up or Ask, and the reader bubble's hand-off), turns the gate on and hosts the dialog (two marked lines); elsewhere, and in JVM tests, the gate is off and the server decides. No `ai_consents` table (the server before 0010) means nothing to ask.
- **Refusals read as the server says them.** A 402 ("You've used today's 150 free messages.") or a 403 (no consent yet) arrives as `ApiException` with the server's sentence, and the brief shows it as is (`BriefErrors`). Tests: `data/ConsentGateTest`, `ui/plans/PlanRefusalsTest`.

## Rules

- **The repo is public.** The app ships only the publishable key (`data/Config.kt`). The service-role key never goes in the app. Never commit a keystore, `keystore.properties` or `local.properties` (all gitignored).
- **No em dashes** in UI copy or docs.
- **The reader** reads only the chat that's open, only when the person asks; stores nothing; logs counts only, never message text or names. Real tests use a test account, and DMs never go in git, screenshots in the repo, or reports.
