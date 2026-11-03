# Chat screens, redesigned

The chat side of Ketchup on the diner-counter design system (`docs/DESIGN.md`): sign-in, the name step, the inbox and its sheets, the chat thread, the chat info sheet and the app icon. Taken on an iPhone 17 Pro Max simulator from the offline previews, November 3, 2026. Every file has a `-light` and a `-dark` version unless noted.

<p>
<img src="signin-light.png" width="200" alt="Sign-in">
<img src="inbox-light.png" width="200" alt="Inbox">
<img src="chat-light.png" width="200" alt="Chat thread">
<img src="info-light.png" width="200" alt="Chat info">
</p>

| File | What it shows |
|---|---|
| `signin` | Wordmark, "Missed 300 messages?", paper email field, "Email me a code" |
| `signin-code` | The code step: 8 mono boxes in two halves, the resend countdown, the keyboard up |
| `name` | "What do your friends call you?" with a monogram that follows the name |
| `inbox` | Serif title, monogram rows, mustard badges, the "302 new · catch up" nudge from 15 unread |
| `inbox-empty` | "Nothing on the counter yet" |
| `new-chat`, `join` | The "+" menu's sheets; Join has 6 code boxes |
| `chat` | The top of Breck: the ketchup "Catch me up" (prefetch landed, so "ready"), the "302 NEW" mark |
| `chat-middle` | Scrolled into the thread: runs from one sender, names in their person colors |
| `chat-jump` | A ref-chip jump mid-hold: the mustard marker behind Maya's "$90 each" |
| `info` | The invite code on a ticket, Share and Copy, members, Leave chat |
| `inbox-xxl-light`, `chat-xxl-light` | Extra Extra Large text (light only) |
| `icon`, `icon-home` | The app icon at 240, 60, 40 and 29 pt, and on the home screen (light only) |

The old look is in `../foundation/` under the same names (`signin`, `inbox`, `inbox-empty`, `name`, `chat`, `info`).

To retake one, launch a DEBUG build with its name (`chat-middle` is `chat` scrolled by hand):

```bash
xcrun simctl launch --terminate-running-process <udid> com.vibetemp.ketchup -screen chat-jump
```
