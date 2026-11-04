# Instagram extractor check

Runs an Instagram thread extractor (an async JS function body, like
`ios/Ketchup/Instagram/InstagramThreadReader.js`) against a page in real WebKit and compares the
result with a ground truth. No Instagram account, no network. The test page,
`ios/Ketchup/Instagram/Fixture/ig-thread-fixture.html`, is a synthetic group DM built the way
Instagram's web DMs are (fictional people, older messages load on scroll-up). Its ground truth,
`ig-thread-fixture.expected.json`, lists all 88 messages. Change both together.

From the repo root (needs Xcode; tested with Xcode 27.0 and Swift 6.4):

```sh
swift scripts/ig-extractor-check/check.swift --html ios/Ketchup/Instagram/Fixture/ig-thread-fixture.html \
  --js ios/Ketchup/Instagram/InstagramThreadReader.js --expected ios/Ketchup/Instagram/Fixture/ig-thread-fixture.expected.json
```

It prints the result JSON, each mismatch (index, field, expected vs got), then `PASS 88/88` or
`FAIL n/88`. Exit codes: 0 pass, 1 fail, 2 the extractor threw or returned `ok: false`, 3 load
failure or timeout. Options: `--url` (default `https://www.instagram.com/direct/t/ketchup-test-fixture/`),
`--args '<json>'` (default `{"maxMessages":300,"maxScrolls":8,"debug":true}`), `--out <file>`,
`--screenshot <png>`, `--timeout <seconds>` (default 90).

The page runs in a 390x844 WKWebView in an off-screen window (nothing appears), in the app's
`WKContentWorld.defaultClient`. WebKit still treats it as visible, so timers and
`requestAnimationFrame` run at full speed. All http(s) and ws(s) loads and any navigation away are
blocked. `console.log` from the extractor and page errors print to stderr.

## The second fixture: Instagram's real structure

`ig-thread-fixture-virtual.html` copies what a redacted outline of the real site showed (Nov 3,
2026): no `role="main"`, a `flex-direction: column-reverse` scroller, and a **virtualized** list
where rows off screen are empty, invisible placeholders that keep their height. Same
conversation; its ground truth differs from the first in 4 lines (view-once and reel
placeholders, plus the pinned bar text in `mustNotContain`).

```sh
swift scripts/ig-extractor-check/check.swift --html ios/Ketchup/Instagram/Fixture/ig-thread-fixture-virtual.html \
  --js ios/Ketchup/Instagram/InstagramThreadReader.js --expected ios/Ketchup/Instagram/Fixture/ig-thread-fixture-virtual.expected.json
```

Run it a second time with `--url 'https://www.instagram.com/direct/t/ketchup-test-fixture/?anchoring=on'`:
that leaves WebKit's scroll anchoring on, so every batch of older messages shifts the view and
hides part of the batch, which the reader has to go back for. All three runs must print
`PASS 88/88`.

## Following ("Until I stop scrolling")

Add `--follow` to any of the commands above (and leave `maxMessages` out of `--args`) to run the
reader the way the app's "Until I stop scrolling" does: `follow` "start", a "look" every quarter
second and "finish", with the app's finish rules (about 3 s after the last new message, 5 s after
the start if none came, 600 messages or 3 minutes). Meanwhile a pretend person scrolls the page's
own scroller, 0.6 of a screen every half second, from a content world of its own: `--person
'up 8, down 2, up 120'` is the default (four ups in a row that go nowhere end a run of ups).
Besides the usual comparison it prints one line of counts, for example `follow read 88 messages,
58 looks, stop enough (quiet), ...; the scroll moved during 0 of 58 looks; dupes 0; left in the
page after finish: nothing`, then checks that "stop" leaves nothing in the page and that another
thread mid-follow (a `pushState`) stops it with `thread_changed`. The two Instagram fixtures must
print `PASS 88/88` and the Snapchat one `PASS 62/62`. With `?anchoring=on` it reads fewer (69 on
Nov 4, 2026): following can't go back for rows the view jumped past.
