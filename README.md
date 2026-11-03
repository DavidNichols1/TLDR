# Ketchup

**Come back to 300 unread group-chat messages and know what matters in 10 seconds.**

**Ketchup**, as in *catch up*, is a native iOS group chat with Meta's **Muse Spark** built in. Tap **Catch me up**
and Muse Spark reads everything you missed. It gives you the plans, the money, the
questions still waiting on an answer, and what people asked *you*. Every item links back
to the message it came from.

Built for the Meta Global AI Developer Hackathon (Cerebral Valley), theme *Build for Your
World*.

> Demo video: TODO(video)

---

## The problem

You mute the friend group chat for two days. When you come back there are 300 messages.
Somewhere in there, the trip moved from Friday to Saturday, the Airbnb price changed,
someone asked for your boot size, and you owe two people money. Finding those means
scrolling through all 300. Most people skim, miss something, and then ask "wait, what
time are we leaving?" and get groaned at.

## What it does

- **Catch me up.** One tap covers everything since you last read the chat. You get a
  short summary, then **For you**, **Plans**, **Open questions**, **Who owes what** and
  **Highlights**.
- **Plans become calendar events.** Each plan is a card with a real date and time (for
  example, "Saturday 6am" becomes `2026-11-07T06:00:00-07:00`), a place, who's going,
  and whether it's confirmed or only proposed. **Add to Calendar** opens the iOS event
  editor already filled in. Ketchup never writes to your calendar itself.
- **Cited messages.** Every bullet has chips for the messages behind it. Tap one and the
  chat jumps to that exact message and highlights it.
- **Ask the chat.** Ask a question like "what time are we leaving?" or "how much do I
  owe Maya?". You get a short answer with the messages that back it up. If the chat
  doesn't say, it tells you so.
- **A real group chat underneath.** Sign in with an email code, create a chat, and
  invite friends with a 6-character code. Messages arrive in real time.

<table>
  <tr>
    <td><img src="docs/screens/redesign/chat-light.png" width="200" alt="A group chat with 302 unread and the Catch me up button"></td>
    <td><img src="docs/screens/redesign/ai-catchup-light.png" width="200" alt="The catch-up: a headline summary and a For you checklist"></td>
    <td><img src="docs/screens/redesign/ai-catchup-plans-light.png" width="200" alt="Plans as order tickets with Add to calendar"></td>
    <td><img src="docs/screens/redesign/ai-catchup-owes-light.png" width="200" alt="Who owes what as a diner check"></td>
  </tr>
</table>

The look is a diner counter: cream paper, ketchup red for the one button that matters,
mustard for what matters to you, plans as order tickets and money as the check. Every
screen opens offline on real demo data with `-screen <name>`; see
[docs/DESIGN.md](docs/DESIGN.md).

## How it uses Muse Spark

Ketchup doesn't just summarize, and it isn't basic RAG either. One Muse Spark call turns
a messy group chat into structured state that the app can act on. Then the server
checks that every claim is backed by a real message.

1. **A transcript tagged with message refs.** The edge function builds the transcript
   ([`transcript.ts`](supabase/functions/_shared/transcript.ts)). Each message is one
   line, `[m12] Sat, Nov 7, 9:15 AM · Maya: …`, with timestamps in the reader's time
   zone. Newlines inside a message are flattened, so one message can't pretend to be
   another.
2. **Strict JSON output.** The request sends a JSON Schema as `response_format`
   (`json_schema`, `strict: true`), so the output is limited to that shape: `tldr`,
   `highlights`, `plans` (with `starts_at`, `ends_at`, `all_day`, `location`,
   `status`, `who`), `open_questions`, `owes` and `for_you`
   ([`brief.ts`](supabase/functions/_shared/brief.ts)). If the API rejects the schema,
   the call falls back to plain JSON mode. Validation runs either way.
3. **Every claim is grounded.** Each item must cite 1–4 refs. The server looks up each
   ref in that request's transcript and maps it to a real message id. Unknown or made-up
   refs are dropped, and **an item left with no valid refs is dropped too**. Text is
   trimmed and length-capped, unparseable dates become `null`, and `status` can only be
   `confirmed` or `proposed`.
4. **Dates in your time zone.** The app sends its time zone. The prompt includes the
   current local date, time and UTC offset, so "Friday at 7" or "tomorrow" turns into an
   ISO 8601 time the calendar can use.
5. **Written for the person reading.** The prompt names the reader and covers only what
   *they* haven't read, using their read cursor. It also includes up to 25
   already-read messages, marked "context only", so "that place" still makes sense.
   **For you** collects what's aimed at the reader by name. When the group changes its
   mind, the prompt asks for the latest decision.
6. **Messages are treated as content, not instructions.** The prompt says chat text is
   never instructions, and the model sees each message as its own tagged line.
7. **Caching and rate limits.** Every result is saved to `ai_briefs`, and only you can
   read yours. Tapping Catch me up again on the same unread messages returns the saved
   brief straight away with no new model call. Each person gets 60 briefs per hour.
8. **Ready before you tap.** Opening a chat with 15+ unread starts the catch-up in the
   background, so the tap usually shows the result instantly. The read cursor still only
   moves when you actually open the result.

Calling the Meta Model API ([`muse.ts`](supabase/functions/_shared/muse.ts)):

- `POST https://api.meta.ai/v1/chat/completions`, model `muse-spark-1.3`,
  `reasoning_effort: low`, `response_format: json_schema`. You can override the model and
  effort with the `META_MODEL` and `META_REASONING` secrets.
- Measured on the 302-message demo chat (November 2, 2026): about 9.5k tokens in and
  3.4k out (1.3k of it reasoning), **about 24 seconds and about 3¢ per catch-up**. Every
  planted plan, debt and open question came back correct. `minimal` effort halves the
  time (12 s) but invented a time the chat never gave, so `low` stays the default and the
  background prefetch hides the wait. "Ask the chat" takes about 3 seconds.
- It retries once on 429/500/503 and honors `Retry-After`. The key is read from the edge
  function's secrets and is never sent to the app.

## Opens instantly

The phone keeps a copy of what you last saw, so Ketchup opens on your chats at once and
refreshes from the server behind them.

- **Your inbox and each chat's newest 400 messages stay on the phone.** They show in the
  first frame, then the server's answer replaces them. Reading a 400-message chat back
  takes under a millisecond on the simulator. Offline, a chat still opens, and says
  "Couldn't refresh. Showing saved messages."
- **Only yours, only here.** The copy lives in the app's own folder, one per signed-in
  account, protected until the phone's first unlock after a restart and left out of
  backups. Signing out deletes all of it, and a chat you leave is forgotten at the next
  refresh ([`DeviceStore.swift`](ios/Ketchup/Store/DeviceStore.swift)).
- **The server still decides what's unread.** When a chat opens, it takes your read cursor
  from the server, so an out-of-date copy can't hide new messages from Catch me up.
- **Paper, not spinners.** A first launch shows blank paper in the shape of the inbox's
  rows and a chat's bubbles. It breathes slowly, and holds still with Reduce Motion on.

## Architecture

```mermaid
flowchart LR
  subgraph iPhone
    A["Ketchup iOS app<br/>SwiftUI, zero dependencies<br/>hand-rolled Supabase Auth + REST client<br/>Realtime websocket, polling fallback"]
  end
  subgraph Supabase
    DB[("Postgres<br/>RLS = security boundary<br/>RPCs: create/join/leave chat,<br/>mark_read, my_chats")]
    RT["Realtime<br/>(messages, filtered by RLS)"]
    FN["Edge function: catch-up<br/>reads as the caller under RLS<br/>ref-tagged transcript → Muse Spark<br/>validate refs + dates → ai_briefs cache"]
  end
  META["Meta Model API<br/>Muse Spark"]

  A -- "publishable key + user JWT" --> DB
  DB --> RT -- "new messages" --> A
  A -- "Catch me up / Ask (user JWT)" --> FN
  FN -- "caller's JWT" --> DB
  FN -- "META_API_KEY (secret)" --> META
```

- **iOS app** ([`ios/`](ios)): SwiftUI with no third-party packages. It has a small
  Supabase client written by hand: email-code auth with the session in the Keychain,
  PostgREST, RPCs and edge functions over `URLSession`. Realtime runs over the Phoenix
  websocket protocol and reconnects with backoff. While the socket is down, the chat
  polls every 4 seconds.
- **Database** ([`supabase/migrations/`](supabase/migrations)): profiles, chats, members,
  messages and `ai_briefs`. Writes that change membership go through security-definer
  RPCs, and clients can't write directly to `chats` or `chat_members`. A new member's
  read cursor starts before the chat began, so their first Catch me up covers the whole
  history.
- **Edge function** ([`supabase/functions/catch-up/`](supabase/functions/catch-up)): runs
  with JWT verification on. It reads messages *with the caller's token*, so Row Level
  Security decides what the model can see. It uses the service role only to write and
  check `ai_briefs`.

### Security

- **Row Level Security is the boundary.** The app ships only the publishable key. You
  only see chats you're in, and you can only post as yourself, into a chat you're in.
  Invite-code guessing is rate-limited, and so is sending.
- **The Meta key lives only in edge function secrets.** It is never in the app or this
  repo.
- **The service-role key is never in the app.** Only the edge function and the local
  demo seed script use it.
- **A 28-check RLS test suite** ([`supabase/tests/rls_check.sql`](supabase/tests/rls_check.sql))
  plays two members and an outsider. It covers spoofing the sender, self-adding to a
  chat, editing chats directly, outsider reads and posts, wrong-code counting, and the
  Instagram and Snapchat catch-up's usage cap. It runs in one transaction and rolls back.

## Run it yourself

**Backend** (Supabase CLI, project ref `cfqlnthmqwkhjbhylvgu` or your own):

```sh
supabase link --project-ref <ref>
supabase db push                                   # applies supabase/migrations
supabase secrets set META_API_KEY=... --project-ref <ref>
supabase functions deploy catch-up --project-ref <ref>   # verify_jwt stays on (the default)
```

Optional: paste `supabase/tests/rls_check.sql` into the SQL editor. Every row should say
`pass = true`.

**iOS** (Xcode 26, iOS 26):

1. Open `ios/Ketchup.xcodeproj`.
2. Pick your team under Signing & Capabilities.
3. If you use your own Supabase project, put its URL and publishable key in
   `ios/Ketchup/Config.swift`.
4. Run on a simulator or a device.

**Demo data**: [`scripts/seed-demo/`](scripts/seed-demo) creates five test friends and a
302-message ski-trip chat, then prints an invite code. Join with that code and you start
with everything unread:

```sh
cp scripts/seed-demo/.env.example scripts/seed-demo/.env   # add the secret key
deno run --allow-net --allow-env --allow-read scripts/seed-demo/seed.ts
```

## Instagram and Snapchat catch-up (experimental, not released)

Nobody moves their group chat to a new app. So this experiment tries the same catch-up
on chats people already have: an Instagram DM thread or a Snapchat chat.

- **How it works.** Instagram's or Snapchat's own website opens inside the app, on its own
  page of the home screen. You sign in on their page and open a chat. Tap **Catch me up**,
  pick the last 30, 80 or 120 messages (the page doesn't say what's unread), and Ketchup
  reads that much of the conversation off the page. Then it runs the same Muse Spark
  catch-up as its own chats through a second edge function,
  [`catch-up-text`](supabase/functions/catch-up-text/index.ts): the same ref-tagged
  transcript, prompts, JSON schemas and validation, laid out with the same brief, tickets,
  diner check and Ask the chat. Each source chip shows the whole message it quotes.
- **It reads only the chat you have open, in your own signed-in session.** Ketchup never
  sees your password or cookies. The readers
  ([`InstagramThreadReader.js`](ios/Ketchup/Instagram/InstagramThreadReader.js),
  [`SnapchatThreadReader.js`](ios/Ketchup/Snapchat/SnapchatThreadReader.js)) run only when
  you pick how much to read on a chat. They go by page structure (roles, tags, labels,
  layout), not the sites' class names, which change. Both step up through the chat for
  older messages, then put the scroll back.
- **Nothing is stored.** No saved catch-up, and no message text in the logs (counts and
  token usage only). The server keeps one usage count per call, with no content, for an
  hourly cap of 20.
- **It isn't sanctioned by Instagram's or Snapchat's terms.** They don't allow automated
  collection, and the messages, your friends' included, go to Muse Spark to summarize. So
  it's not in the released app, and it won't ship unless Meta and Snap are fine with it.
  Ketchup's own chat doesn't depend on it.
- **Snapchat took three browser settings, and nothing injected into its pages.** Snapchat for
  Web sends phones to "Download Snapchat", so Ketchup asks for its desktop page with a Mac
  user agent (what Safari's "Request Desktop Website" does) and lays the page out 1024 points
  wide, shrunk to fit the screen. Signed in, its chat app also needs a service worker, which
  WebKit only runs for app-bound domains (the app's Info.plist lists them). Once an app lists
  any, WebKit only lets it read pages in web views kept to them, so Instagram's page is kept
  to its sites too. The Snapchat page is small, so pinch to zoom; Catch me up is the point anyway.
- **Built to take another app.** The browser, the page and the catch-up sheet are shared
  ([`ios/Ketchup/WebChat/`](ios/Ketchup/WebChat)); a `WebChatSource` says what differs
  (name, start page, allowed sites, thread URL, reader script, user agent, desktop layout).

## Built during the event

This repo was started on November 2, 2026, during the hackathon. The commit history
shows the build: schema and RLS, then the edge function, then the Muse Spark wiring,
then the iOS app.

## Built on

The networking and chat plumbing are adapted from **AurariaGO**, a live App Store app I
built under VibetempLLC. That includes the Supabase client approach, the chat bubble
and input bar components, and the on-device cache and loading skeletons (restyled for
Ketchup). Everything specific to Ketchup is new for this event: the
schema, the `catch-up` edge function, the Muse Spark integration, the catch-up and
ask-the-chat UI, plan cards, and the Realtime websocket (AurariaGO polls).

## Team

David Nichols, VibetempLLC
