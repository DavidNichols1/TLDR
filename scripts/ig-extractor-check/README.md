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
