# Demo seed: a group chat with ~300 unread

This script sets up the demo moment: you join a busy group chat and it has about
300 messages you haven't read.

It creates five test friends (Maya, Jordan, Priya, Sam, Theo), a chat called
**Breck Weekend 🎿**, and 302 messages spread over three days. The friends plan a ski
weekend while "David" is away at a hackathon. When you join with the invite code,
every message is unread. Then you tap **Catch me up**.

The conversation is in [`conversation.ts`](conversation.ts). It's written to be full of
things Muse Spark should find:

- **Plans that change.** Leaving Friday at 4pm becomes Saturday at 6:00am from Maya's.
  Hearthstone dinner moves from Friday 7:30 to Saturday 7:30. The grocery run moves to
  Friday 7pm.
- **Money that changes.** The Airbnb starts at $140 each, then a refund makes it $90.
  Maya sends Jordan and Priya $50 back. Gas is $20 per rider. Sam has owed Theo $45
  since October.
- **Questions nobody answers.** The hot tub, Jordan's snow tires, who sleeps where.
  There are also some questions that do get answered, so they should *not* come back
  as open.
- **Things aimed at David.** His boot size, confirming for Hearthstone, his $90, his
  $20 for gas, the speaker and Catan, and Root Down.
- Side threads and banter: Pickles the dog, a playlist war, costume day, Priya's exam.

## Run it

You need [Deno](https://deno.com) (`brew install deno`) and the project's
**secret key** (the service-role key):

> Supabase dashboard → your project → **Project Settings → API Keys** → copy the
> **secret** key (`sb_secret_…`). Older projects can use the `service_role` key
> under **Legacy API keys** instead.

This key skips Row Level Security, so it only goes in this local, gitignored file.
Never put it in the app or in a commit.

```sh
cd /Users/david/Projects/TLDR
cp scripts/seed-demo/.env.example scripts/seed-demo/.env
# paste the secret key into scripts/seed-demo/.env

# 1. Preview it. This writes nothing and doesn't need the key.
deno run --allow-net --allow-env --allow-read scripts/seed-demo/seed.ts --dry-run

# 2. Seed it.
deno run --allow-net --allow-env --allow-read scripts/seed-demo/seed.ts
```

Then in the app (sign in with your own account):

1. Use **David** as your display name (it's on the name step after sign-up). "For you"
   items are written to David, and Muse Spark matches them by your name.
2. Tap **Join**, enter the invite code the script printed, and open the chat.
3. You should see about 300 unread messages. Tap **Catch me up**.

**Seed first, then join.** A new member's unread count starts from when the chat was
created. The script backdates the chat so that everything counts as unread.

## What you should see

From the seed:

```
  user Maya    tldr.demo+maya@example.com  (created)
  ...
  chat "Breck Weekend 🎿" <uuid>  (created)
  inserted 302 messages (0 already there)
  dated 302 messages
Messages in chat: 0 → 302

  INVITE CODE:  ABC234
```

It also prints the real dates. The conversation ends on the most recent Monday,
Tuesday or Wednesday that's already over, and the trip is the Friday to Sunday after
that.

From **Catch me up** (open the brief and check it against this list):

- **Plans:** leave Saturday 6:00am from Maya's (not Friday 4pm). Hearthstone Saturday
  7:30pm (not Friday). Rentals pickup at Christy Sports Friday 6pm. Groceries at King
  Soopers Friday 7pm. Root Down Thursday 7:30 (for 4). A-Basin Sunday, leaving by 2pm.
  Times should have the right dates on them. **Add to Calendar** should prefill them.
- **Owes:** David owes Maya $90 (not $140). Sam and David each owe Jordan $20 for gas.
  Sam owes Theo $45. Sam and Theo have already paid Maya, so they shouldn't be listed
  as owing her.
- **Open questions:** the hot tub, Jordan's snow tires, who sleeps where, and David's
  boot size, Hearthstone headcount and Root Down replies.
- **For you:** confirm for Hearthstone by Thursday noon, boot size for rentals, $90 to
  Maya, $20 to Jordan, bring the speaker and Catan, you're in Jordan's car (be at
  Maya's at 5:45am).
- Every item has message chips. Tapping a chip jumps to that message.

## Re-running

Running it again is safe. Message ids come from the chat id and the script line, so
nothing gets duplicated. A re-run keeps the dates it already used.

| Flag | What it does |
|---|---|
| `--dry-run` | Prints the timeline, messages per sender and per day, and every planted item. Writes nothing. |
| `--rearm` | Makes the chat fully unread again for everyone who isn't a demo friend (you), and deletes your saved catch-ups for this chat, so the next tap calls Muse Spark fresh. Use this before each take of the demo video. |
| `--retime` | Moves the conversation so it ends just now, for example if you re-record days later. Run it with `--rearm`. |
| `--end-date=YYYY-MM-DD` | Puts the last day of the conversation on a date you choose. Use a Monday, Tuesday or Wednesday. |
| `--reset` | Deletes the demo friends' messages in the chat and seeds them again. Use this after editing `conversation.ts`. Your own messages stay. |

The script also prints each non-demo member's unread count. If yours says `0 unread`,
run it with `--rearm`.

## How it writes (for the curious)

- The accounts come from the Auth admin API with `email_confirm: true`. They use
  `@example.com` addresses, which never get mail. The script renames their profile
  rows, which the sign-up trigger creates.
- `create_chat()` needs a signed-in user, so the script does the same work directly. It
  inserts a `chats` row with a fresh six-character code (same alphabet, no 0/O/1/I) and
  adds the members. The member-count trigger still runs.
- The `messages_hygiene` trigger sets `created_at = now()` on every insert, even for the
  service role. So the script inserts messages in batches of 100, then sets each
  message's `created_at` with an update (that trigger doesn't run on updates). Last, it
  backdates `chats.created_at` and the summary columns so that new members see
  everything as unread.
