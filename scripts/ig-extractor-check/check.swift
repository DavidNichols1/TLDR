// Cetchup: run an Instagram thread extractor against an HTML page in real WebKit, offscreen,
// and compare what it returns with a ground-truth file.
//
//   swift scripts/ig-extractor-check/check.swift --html <file> --js <file> [--expected <file>]
//       [--url <baseURL>] [--args '<json>'] [--size <W>x<H>] [--out <file>] [--screenshot <png>] [--timeout <seconds>]
//       [--follow] [--person '<moves>']
//
// --follow runs "Until I stop scrolling" the way the app does: the extractor with follow "start",
// "look" every quarter second and "finish" with the app's finish rules, while a pretend person
// scrolls the page's own scroller from a third content world (see `Follow` below).
//
// The page goes into a 390x844 WKWebView with loadHTMLString(html, baseURL: url). The web view
// sits in a borderless window parked far off every screen, so nothing ever appears, but WebKit
// still treats the page as visible (no hidden-page timer throttling, requestAnimationFrame runs).
// The --js file is the BODY of an async function. It runs through callAsyncJavaScript in
// WKContentWorld.defaultClient, the isolated world the app uses, with the --args keys as local
// variables. It should return a JSON string (an object works too) shaped like
//   {"ok": true, "title": ..., "isGroup": ..., "messages": [{"sender","text","isMe","at","atLabel"}], "stats": {...}}
//
// Nothing reaches the network, even though the base URL is instagram.com: a content rule list
// blocks every http(s) and ws(s) load, and any navigation away from the page is cancelled.
// console.log from the extractor and errors thrown by the page are printed to stderr.
//
// Exit codes: 0 ok (or PASS), 1 FAIL against --expected, 2 the extractor threw or said ok:false,
// 3 the page didn't load, WebKit crashed or the timeout hit, 64 bad arguments.

import AppKit
import WebKit

// MARK: - Options

struct Options: Sendable {
    var html = ""
    var js = ""
    var expected: String?
    var url = "https://www.instagram.com/direct/t/ketchup-test-fixture/"
    var args = #"{"maxMessages":300,"maxScrolls":8,"debug":true}"#
    var out: String?
    var screenshot: String?
    var timeout = 90.0
    /// The window in points: a phone by default; Snapchat's page is a computer's (`--size 1024x768`).
    var width = 390.0
    var height = 844.0
    /// "Until I stop scrolling" instead of one call.
    var follow = false
    /// The pretend person's moves while following: "up 8, down 2, up 80" scrolls up 8 times, down
    /// twice, then up until the top, 0.6 of a screen every half second.
    var person = "up 8, down 2, up 120"
}

func eprint(_ line: String) {
    FileHandle.standardError.write(Data((line + "\n").utf8))
}

/// stdout without buffering, so it stays in order with the stderr notes.
func say(_ line: String = "") {
    FileHandle.standardOutput.write(Data((line + "\n").utf8))
}

func usage(_ problem: String? = nil) -> Never {
    if let problem { eprint("error: \(problem)") }
    eprint("""
    usage: swift scripts/ig-extractor-check/check.swift --html <file> --js <file> [--expected <file>]
               [--url <baseURL>] [--args '<json>'] [--size <W>x<H>] [--out <file>] [--screenshot <png>] [--timeout <seconds>]
               [--follow] [--person '<moves>']
    """)
    exit(64)
}

func parseOptions(_ argv: [String]) -> Options {
    var o = Options()
    var i = 0
    func value(_ flag: String) -> String {
        i += 1
        guard i < argv.count else { usage("\(flag) needs a value") }
        return argv[i]
    }
    while i < argv.count {
        let flag = argv[i]
        switch flag {
        case "--html": o.html = value(flag)
        case "--js": o.js = value(flag)
        case "--expected": o.expected = value(flag)
        case "--url": o.url = value(flag)
        case "--args": o.args = value(flag)
        case "--out": o.out = value(flag)
        case "--screenshot": o.screenshot = value(flag)
        case "--size":
            let wh = value(flag).split(separator: "x").compactMap { Double($0) }
            guard wh.count == 2, wh[0] > 0, wh[1] > 0 else { usage("--size needs <width>x<height>, like 1024x768") }
            o.width = wh[0]
            o.height = wh[1]
        case "--follow": o.follow = true
        case "--person": o.person = value(flag)
        case "--timeout":
            guard let seconds = Double(value(flag)), seconds > 0 else { usage("--timeout needs a number of seconds") }
            o.timeout = seconds
        case "-h", "--help": usage()
        default: usage("unknown argument \(flag)")
        }
        i += 1
    }
    if o.html.isEmpty || o.js.isEmpty { usage("--html and --js are required") }
    return o
}

/// Where the compiled network block list lives for this run; removed on the way out.
let rulesDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent("ketchup-ig-check-\(ProcessInfo.processInfo.processIdentifier)")

func finish(_ code: Int32) -> Never {
    try? FileManager.default.removeItem(at: rulesDirectory)
    exit(code)
}

func readText(_ path: String) -> String {
    do { return try String(contentsOfFile: path, encoding: .utf8) } catch {
        eprint("error: can't read \(path): \(error.localizedDescription)")
        exit(64)
    }
}

func prettyJSON(_ object: Any) -> String {
    guard JSONSerialization.isValidJSONObject(object),
          let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
          let text = String(data: data, encoding: .utf8) else { return String(describing: object) }
    return text
}

/// A string as a one-line JSON literal, so newlines and quotes stay visible in the report.
func quoted(_ s: String?) -> String {
    guard let s else { return "null" }
    guard let data = try? JSONSerialization.data(withJSONObject: [s], options: [.withoutEscapingSlashes]),
          let text = String(data: data, encoding: .utf8) else { return "\"\(s)\"" }
    return String(text.dropFirst().dropLast())
}

// MARK: - Comparing with the ground truth

struct Message {
    var sender: String
    var isMe: Bool
    var text: String
    var atLabel: String?

    init(_ any: Any) {
        let d = any as? [String: Any] ?? [:]
        sender = d["sender"] as? String ?? ""
        isMe = d["isMe"] as? Bool ?? false
        text = d["text"] as? String ?? ""
        atLabel = d["atLabel"] as? String
    }

    var summary: String {
        "sender=\(quoted(sender)) isMe=\(isMe) text=\(quoted(text)) atLabel=\(quoted(atLabel))"
    }
}

/// Whitespace collapsed inside each line, blank lines dropped, lines joined with "\n".
func normalized(_ s: String?) -> String {
    guard let s else { return "" }
    let unified = s.replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
        .replacingOccurrences(of: "\u{200B}", with: "")
        .replacingOccurrences(of: "\u{FEFF}", with: "")
    return unified.split(separator: "\n", omittingEmptySubsequences: false)
        .map { $0.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ") }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
}

func normalizedLabel(_ s: String?) -> String? {
    let n = normalized(s)
    return n.isEmpty ? nil : n
}

/// Character bigrams, for a cheap text similarity (Dice coefficient) used only to line messages up.
struct Bigrams {
    let counts: [String: Int]
    let total: Int

    init(_ s: String) {
        let chars = Array("\u{2}" + s.lowercased() + "\u{3}")
        var counts: [String: Int] = [:]
        for k in 0..<(chars.count - 1) { counts[String(chars[k]) + String(chars[k + 1]), default: 0] += 1 }
        self.counts = counts
        total = chars.count - 1
    }

    func similarity(_ other: Bigrams) -> Double {
        var common = 0
        for (gram, n) in counts { if let m = other.counts[gram] { common += min(n, m) } }
        return Double(2 * common) / Double(total + other.total)
    }
}

/// Lines the two lists up (Needleman-Wunsch), so one missing or extra message shows up as just
/// that and doesn't shift every later row into a mismatch. Returns (expected index, got index) pairs;
/// nil on one side means missing or extra.
func align(_ expected: [Message], _ got: [Message]) -> [(Int?, Int?)] {
    let n = expected.count, m = got.count
    let eText = expected.map { Bigrams(normalized($0.text)) }, gText = got.map { Bigrams(normalized($0.text)) }
    let eWho = expected.map { "\($0.isMe)|\(normalized($0.sender))" }, gWho = got.map { "\($0.isMe)|\(normalized($0.sender))" }
    let eAt = expected.map { normalizedLabel($0.atLabel) }, gAt = got.map { normalizedLabel($0.atLabel) }
    let gap = -0.35
    func pair(_ i: Int, _ j: Int) -> Double {
        var s = eText[i].similarity(gText[j])
        if eWho[i] == gWho[j] { s += 0.2 }
        if eAt[i] == gAt[j] { s += 0.1 }
        return s - 0.3   // two unrelated messages in the same spot still pair up (shown as a field mismatch)
    }
    var score = [[Double]](repeating: [Double](repeating: 0, count: m + 1), count: n + 1)
    var step = [[UInt8]](repeating: [UInt8](repeating: 0, count: m + 1), count: n + 1)
    for i in 0...n {
        for j in 0...m where i > 0 || j > 0 {
            var best = -Double.infinity
            var move: UInt8 = 0
            if i > 0, j > 0, score[i - 1][j - 1] + pair(i - 1, j - 1) > best { best = score[i - 1][j - 1] + pair(i - 1, j - 1); move = 1 }
            if i > 0, score[i - 1][j] + gap > best { best = score[i - 1][j] + gap; move = 2 }
            if j > 0, score[i][j - 1] + gap > best { best = score[i][j - 1] + gap; move = 3 }
            score[i][j] = best
            step[i][j] = move
        }
    }
    var ops: [(Int?, Int?)] = []
    var i = n, j = m
    while i > 0 || j > 0 {
        switch step[i][j] {
        case 1: ops.append((i - 1, j - 1)); i -= 1; j -= 1
        case 2: ops.append((i - 1, nil)); i -= 1
        default: ops.append((nil, j - 1)); j -= 1
        }
    }
    return ops.reversed()
}

func compare(result: [String: Any], resultText: String, expectedPath: String) -> Int32 {
    guard let data = FileManager.default.contents(atPath: expectedPath),
          let truth = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        eprint("error: can't read \(expectedPath) as a JSON object")
        return 64
    }
    let expected = (truth["messages"] as? [Any] ?? []).map(Message.init)
    let got = (result["messages"] as? [Any] ?? []).map(Message.init)
    var problems: [String] = []

    say()
    say("Compare with \(expectedPath): expected \(expected.count) messages, got \(got.count)")
    let eTitle = truth["title"] as? String, gTitle = result["title"] as? String
    if normalized(eTitle) == normalized(gTitle) {
        say("  title    ok  \(quoted(gTitle))")
    } else {
        say("  title    MISMATCH  expected \(quoted(eTitle)) got \(quoted(gTitle))")
        problems.append("title mismatch")
    }
    let eGroup = truth["isGroup"] as? Bool, gGroup = result["isGroup"] as? Bool
    if eGroup == gGroup {
        say("  isGroup  ok  \(gGroup.map { "\($0)" } ?? "null")")
    } else {
        say("  isGroup  MISMATCH  expected \(eGroup.map { "\($0)" } ?? "null") got \(gGroup.map { "\($0)" } ?? "null")")
        problems.append("isGroup mismatch")
    }
    for needle in truth["mustNotContain"] as? [String] ?? [] where resultText.contains(needle) {
        say("  LEAK     the result contains \(quoted(needle))")
        problems.append("leaked \(quoted(needle))")
    }

    var full = 0, missing = 0, extra = 0, wrong = 0
    for (e, g) in align(expected, got) {
        switch (e, g) {
        case let (e?, g?):
            let x = expected[e], y = got[g]
            var diffs: [String] = []
            if normalized(x.sender) != normalized(y.sender) { diffs.append("sender: expected \(quoted(x.sender)) got \(quoted(y.sender))") }
            if x.isMe != y.isMe { diffs.append("isMe: expected \(x.isMe) got \(y.isMe)") }
            if normalized(x.text) != normalized(y.text) { diffs.append("text: expected \(quoted(x.text)) got \(quoted(y.text))") }
            if normalizedLabel(x.atLabel) != normalizedLabel(y.atLabel) { diffs.append("atLabel: expected \(quoted(x.atLabel)) got \(quoted(y.atLabel))") }
            if diffs.isEmpty { full += 1 } else {
                wrong += 1
                for d in diffs { say("  #\(e) (got #\(g)) \(d)") }
            }
        case let (e?, nil):
            missing += 1
            say("  #\(e) MISSING  \(expected[e].summary)")
        case let (nil, g?):
            extra += 1
            say("  got #\(g) EXTRA  \(got[g].summary)")
        default:
            break
        }
    }

    var notes: [String] = []
    if missing > 0 { notes.append("\(missing) missing") }
    if extra > 0 { notes.append("\(extra) extra") }
    if wrong > 0 { notes.append("\(wrong) with wrong fields") }
    notes += problems
    let pass = full == expected.count && extra == 0 && problems.isEmpty
    say(pass ? "PASS \(full)/\(expected.count)" : "FAIL \(full)/\(expected.count)" + (notes.isEmpty ? "" : " (\(notes.joined(separator: ", ")))"))
    return pass ? 0 : 1
}

// MARK: - WebKit

@MainActor
final class Harness: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    let options: Options
    let baseURL: URL
    var webView: WKWebView?
    var window: NSWindow?
    var loadWaiter: CheckedContinuation<Void, Error>?
    var firstNavigationAllowed = false

    init(options: Options) {
        self.options = options
        guard let url = URL(string: options.url), url.scheme != nil else { usage("--url isn't a URL: \(options.url)") }
        baseURL = url
    }

    func run() async -> Int32 {
        let html = readText(options.html)
        let js = readText(options.js)
        guard let args = (try? JSONSerialization.jsonObject(with: Data(options.args.utf8))) as? [String: Any] else {
            usage("--args must be a JSON object")
        }

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let content = config.userContentController
        content.add(self, contentWorld: .defaultClient, name: "ketchupCheckConsole")
        content.add(self, contentWorld: .page, name: "ketchupCheckPageError")
        content.addUserScript(WKUserScript(source: Self.consoleShim, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: .defaultClient))
        content.addUserScript(WKUserScript(source: Self.pageErrorShim, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: .page))
        if let blocker = await networkBlocker() {
            content.add(blocker)
        } else {
            eprint("[check] warning: the network block list didn't compile; only the navigation filter is on")
        }

        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: options.width, height: options.height), configuration: config)
        web.appearance = NSAppearance(named: .aqua)
        web.navigationDelegate = self
        // The window is off screen, which macOS reports as occluded, and WebKit would then treat the
        // page as hidden. This WebKit setting (private, test-only use) turns that check off.
        if web.responds(to: NSSelectorFromString("_setWindowOcclusionDetectionEnabled:")) {
            web.setValue(false, forKey: "windowOcclusionDetectionEnabled")
        }
        let offscreen = NSRect(x: -20000, y: -20000, width: options.width, height: options.height)
        let win = NSWindow(contentRect: offscreen, styleMask: [.borderless], backing: .buffered, defer: false)
        win.isReleasedWhenClosed = false
        win.ignoresMouseEvents = true
        win.contentView = web
        win.setFrame(offscreen, display: false)
        win.orderFrontRegardless()
        webView = web
        window = win

        do {
            try await withCheckedThrowingContinuation { (waiter: CheckedContinuation<Void, Error>) in
                loadWaiter = waiter
                web.loadHTMLString(html, baseURL: baseURL)
            }
        } catch {
            eprint("error: the page didn't load: \(error.localizedDescription)")
            return 3
        }
        try? await Task.sleep(nanoseconds: 500_000_000)

        let pageInfo = (try? await web.callAsyncJavaScript(
            "return JSON.stringify({href: location.href, visibility: document.visibilityState, viewport: innerWidth + 'x' + innerHeight})",
            arguments: [:], in: nil, contentWorld: .page)) as? String
        eprint("[check] page ready \(pageInfo ?? "(no info)")")

        let started = Date()
        let raw: Any?
        do {
            if options.follow {
                guard let moves = Follow.moves(options.person) else { usage("--person needs moves like 'up 8, down 2, up 120'") }
                raw = try await Follow(web: web, js: js, args: args, moves: moves).run()
            } else {
                raw = try await web.callAsyncJavaScript(js, arguments: args, in: nil, contentWorld: .defaultClient)
            }
        } catch {
            eprint("error: the extractor threw: \(Self.describe(error))")
            return 2
        }
        eprint(String(format: "[check] extractor returned after %.1fs", Date().timeIntervalSince(started)))

        if let path = options.screenshot { await saveScreenshot(web, to: path) }

        let result: [String: Any]
        let resultText: String
        switch raw {
        case let text as String:
            guard let object = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] else {
                say(text)
                eprint("error: the extractor returned a string that isn't a JSON object")
                return 2
            }
            result = object
            resultText = text
        case let object as [String: Any]:
            result = object
            resultText = prettyJSON(object)
        default:
            eprint("error: the extractor returned \(raw.map { "a \(type(of: $0))" } ?? "nothing (undefined or null)"), not a JSON string")
            return 2
        }

        let pretty = prettyJSON(result)
        if let out = options.out {
            do {
                try (pretty + "\n").write(toFile: out, atomically: true, encoding: .utf8)
                eprint("[check] result written to \(out)")
            } catch {
                eprint("error: can't write \(out): \(error.localizedDescription)")
                return 64
            }
        } else {
            say(pretty)
        }

        guard result["ok"] as? Bool == true else {
            eprint("error: the extractor returned ok: \((result["ok"] as? Bool).map { "\($0)" } ?? "(missing)"), error: \(result["error"].map { "\($0)" } ?? "(none given)")")
            return 2
        }
        if let expectedPath = options.expected {
            return compare(result: result, resultText: resultText, expectedPath: expectedPath)
        }
        return 0
    }

    private func networkBlocker() async -> WKContentRuleList? {
        // Content rule regexes have no "|", so one rule per scheme. The page itself (type
        // "document") is left alone: it comes from loadHTMLString, not the network.
        let types = #"["image", "style-sheet", "script", "font", "raw", "svg-document", "media", "popup", "ping", "fetch", "websocket", "other"]"#
        let rules = "[" + ["^https?://", "^wss?://", "^ftp://"].map {
            #"{"trigger": {"url-filter": "\#($0)", "resource-type": \#(types)}, "action": {"type": "block"}}"#
        }.joined(separator: ", ") + "]"
        try? FileManager.default.createDirectory(at: rulesDirectory, withIntermediateDirectories: true)
        guard let store = WKContentRuleListStore(url: rulesDirectory) else { return nil }
        do {
            return try await store.compileContentRuleList(forIdentifier: "no-network", encodedContentRuleList: rules)
        } catch {
            eprint("[check] block list error: \(error.localizedDescription)")
            return nil
        }
    }

    private func saveScreenshot(_ web: WKWebView, to path: String) async {
        do {
            let image = try await web.takeSnapshot(configuration: nil)
            guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]) else {
                eprint("[check] screenshot failed: couldn't encode a PNG")
                return
            }
            try png.write(to: URL(fileURLWithPath: path))
            eprint("[check] screenshot saved to \(path)")
        } catch {
            eprint("[check] screenshot failed: \(error.localizedDescription)")
        }
    }

    static func describe(_ error: Error) -> String {
        let info = (error as NSError).userInfo
        var parts: [String] = []
        if let message = info["WKJavaScriptExceptionMessage"] { parts.append("\(message)") }
        // callAsyncJavaScript usually reports line 0; only show a real position.
        if let line = info["WKJavaScriptExceptionLineNumber"] as? Int, line > 0 { parts.append("line \(line)") }
        if let column = info["WKJavaScriptExceptionColumnNumber"] as? Int, column > 0 { parts.append("column \(column)") }
        return parts.isEmpty ? error.localizedDescription : parts.joined(separator: ", ")
    }

    // console.* in the extractor's world goes to stderr as [js log] lines.
    static let consoleShim = """
    (() => {
      const show = (a) => {
        if (typeof a === 'string') return a;
        if (a === undefined) return 'undefined';
        if (a instanceof Element) return '<' + a.tagName.toLowerCase() + '>';
        try { return JSON.stringify(a); } catch (e) { return String(a); }
      };
      for (const level of ['log', 'info', 'warn', 'error', 'debug']) {
        const original = console[level];
        console[level] = function (...args) {
          try { window.webkit.messageHandlers.ketchupCheckConsole.postMessage({ level, text: args.map(show).join(' ') }); } catch (e) {}
          if (original) original.apply(console, args);
        };
      }
    })();
    """

    // Uncaught errors in the page's own scripts go to stderr as [page error] lines.
    static let pageErrorShim = """
    (() => {
      const post = (text) => { try { window.webkit.messageHandlers.ketchupCheckPageError.postMessage({ level: 'error', text: String(text) }); } catch (e) {} };
      window.addEventListener('error', (e) => post((e.message || 'error') + (e.filename ? ' (' + e.filename + ':' + e.lineno + ')' : '')));
      window.addEventListener('unhandledrejection', (e) => post('unhandled rejection: ' + ((e.reason && e.reason.message) || e.reason)));
    })();
    """

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        if !firstNavigationAllowed {
            firstNavigationAllowed = true
            return .allow
        }
        let url = navigationAction.request.url
        if let url, url.scheme == "about" || isFragmentOnly(url) { return .allow }
        eprint("[check] blocked a navigation to \(url?.absoluteString ?? "(no URL)"); the page stays put")
        return .cancel
    }

    private func isFragmentOnly(_ url: URL) -> Bool {
        func withoutFragment(_ u: URL) -> String {
            var parts = URLComponents(url: u, resolvingAgainstBaseURL: false)
            parts?.fragment = nil
            return parts?.string ?? u.absoluteString
        }
        return url.fragment != nil && withoutFragment(url) == withoutFragment(baseURL)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadWaiter?.resume()
        loadWaiter = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        navigationFailed(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        navigationFailed(error)
    }

    private func navigationFailed(_ error: Error) {
        if let waiter = loadWaiter {
            loadWaiter = nil
            waiter.resume(throwing: error)
        } else if (error as NSError).code != 102 { // 102: a navigation we cancelled above
            eprint("[check] navigation error: \(error.localizedDescription)")
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        eprint("error: the WebKit content process crashed")
        finish(3)
    }

    // MARK: WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        let body = message.body as? [String: Any] ?? [:]
        let level = body["level"] as? String ?? "log"
        let text = body["text"] as? String ?? "\(message.body)"
        eprint(message.name == "ketchupCheckPageError" ? "[page \(level)] \(text)" : "[js \(level)] \(text)")
    }
}

// MARK: - Following

/// "Until I stop scrolling", as WebChatBrowser.follow runs it: the extractor never scrolls; a
/// pretend person does, from their own content world, and the extractor reads what they scroll
/// past. The same finish rules as the app: about 3 s after the last new message, 5 s after the
/// start if none came, 600 messages, or 3 minutes. Prints counts only, then checks that
/// nothing was left in the page, that "stop" forgets, and that a changed thread stops it.
@MainActor
struct Follow {
    let web: WKWebView
    let js: String
    let args: [String: Any]
    let moves: [Int]   // -1 up, +1 down, one per half second

    static let quiet = 3.0, idle = 5.0, longest = 180.0, poll = 0.25, most = 600
    static let person = WKContentWorld.world(name: "ketchup-check-person")

    static func moves(_ plan: String) -> [Int]? {
        var out: [Int] = []
        for part in plan.split(separator: ",") {
            let words = part.split(separator: " ")
            guard words.count == 2, let n = Int(words[1]), n >= 0, words[0] == "up" || words[0] == "down" else { return nil }
            out += Array(repeating: words[0] == "up" ? -1 : 1, count: n)
        }
        return out
    }

    func call(_ step: String, stop: String? = nil) async throws -> [String: Any] {
        var a = args
        a["maxMessages"] = Self.most
        a["follow"] = step
        if let stop { a["stop"] = stop }
        let raw = try await web.callAsyncJavaScript(js, arguments: a, in: nil, contentWorld: .defaultClient)
        guard let text = raw as? String, let object = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] else {
            throw NSError(domain: "follow", code: 1, userInfo: [NSLocalizedDescriptionKey: "follow \(step) returned no JSON"])
        }
        return object
    }

    /// The person: the page's biggest scroller, moved 0.6 of its height. Returns how far it went.
    func scroll(_ direction: Int) async -> Double {
        let script = """
        const sc = [...document.querySelectorAll('*')]
          .filter((el) => /(auto|scroll)/.test(getComputedStyle(el).overflowY) && el.scrollHeight > el.clientHeight + 8)
          .sort((a, b) => (b.scrollHeight - b.clientHeight) - (a.scrollHeight - a.clientHeight))[0];
        if (!sc) return 0;
        const before = sc.scrollTop;
        if (direction !== 0) sc.scrollTop = before + direction * Math.round(sc.clientHeight * 0.6);
        return direction === 0 ? before : Math.abs(sc.scrollTop - before);
        """
        let raw = try? await web.callAsyncJavaScript(script, arguments: ["direction": direction], in: nil, contentWorld: Self.person)
        return (raw as? NSNumber)?.doubleValue ?? 0
    }

    func run() async throws -> Any? {
        let started = Date()
        var reply = try await call("start")
        guard reply["ok"] as? Bool == true else { return try JSONSerialization.data(withJSONObject: reply).string }
        var found = reply["found"] as? Int ?? 0
        let first = found
        var lastNew: Date?
        var looks = 1, ups = 0, downs = 0, stuck = 0, movedInLook = 0, next = 0
        var nextMove = started.addingTimeInterval(1)
        var stop = "enough", why = "quiet"
        while true {
            let now = Date(), age = now.timeIntervalSince(started)
            if found >= Self.most { why = "most"; break }
            if age >= Self.longest { stop = "budget"; why = "budget"; break }
            if lastNew == nil, age >= Self.idle { why = "idle"; break }
            if let lastNew, now.timeIntervalSince(lastNew) >= Self.quiet { break }
            if now >= nextMove, next < moves.count {
                let direction = moves[next]
                let went = await scroll(direction)
                if direction < 0 { ups += 1 } else { downs += 1 }
                // At the top with nothing more coming: the rest of this run of ups is done.
                stuck = direction < 0 && went < 1 ? stuck + 1 : 0
                next += 1
                if stuck >= 4 { while next < moves.count, moves[next] < 0 { next += 1 }; stuck = 0 }
                nextMove = Date().addingTimeInterval(0.5)
            }
            try await Task.sleep(nanoseconds: UInt64(Self.poll * 1e9))
            let before = await scroll(0)
            reply = try await call("look")
            let after = await scroll(0)
            if before != after { movedInLook += 1 }
            guard reply["ok"] as? Bool == true else { return try JSONSerialization.data(withJSONObject: reply).string }
            looks += 1
            if let n = reply["found"] as? Int, n > found { found = n; lastNew = Date() }
        }
        let result = try await call("finish", stop: stop)
        let stats = result["stats"] as? [String: Any] ?? [:]
        let left = try await web.callAsyncJavaScript("return typeof globalThis.ketchupFollow", arguments: [:], in: nil, contentWorld: .defaultClient) as? String
        eprint("[check] follow read \(stats["found"] ?? "?") messages, \(looks) looks, stop \(stop) (\(why)), \(stats["ms"] ?? "?") ms; " +
               "\(first) on screen at the start; the person scrolled \(ups) up and \(downs) down; the scroll moved during \(movedInLook) of \(looks) looks; " +
               "dupes \(stats["dupes"] ?? "?"); left in the page after finish: \(left == "undefined" ? "nothing" : left ?? "?")")

        // "stop" forgets everything.
        _ = try await call("start")
        _ = try await call("stop")
        let afterStop = try await web.callAsyncJavaScript("return typeof globalThis.ketchupFollow", arguments: [:], in: nil, contentWorld: .defaultClient) as? String
        eprint("[check] after start then stop, left in the page: \(afterStop == "undefined" ? "nothing" : afterStop ?? "?")")
        // A different thread mid-follow (the site changes pages with pushState) stops it.
        _ = try await call("start")
        _ = try await web.callAsyncJavaScript("const p = location.pathname; history.pushState(null, '', p.replace(/[^/]+\\/?$/, 'another-thread')); return p",
                                              arguments: [:], in: nil, contentWorld: Self.person)
        let changed = try await call("look")
        let afterChange = try await web.callAsyncJavaScript("return typeof globalThis.ketchupFollow", arguments: [:], in: nil, contentWorld: .defaultClient) as? String
        _ = try await web.callAsyncJavaScript("history.back(); return 1", arguments: [:], in: nil, contentWorld: Self.person)
        eprint("[check] another thread mid-follow: \(changed["error"] ?? "no error"), left in the page: \(afterChange == "undefined" ? "nothing" : afterChange ?? "?")")
        return try JSONSerialization.data(withJSONObject: result).string
    }
}

extension Data {
    var string: String { String(decoding: self, as: UTF8.self) }
}

// MARK: - Main

let options = parseOptions(Array(CommandLine.arguments.dropFirst()))

// Overlay scrollbars, as on iOS. With a mouse attached (or "Show scroll bars: Always") macOS
// reserves a 15-17px scrollbar gutter, which would make the page narrower than 390px.
UserDefaults.standard.setVolatileDomain(["AppleShowScrollBars": "WhenScrolling"], forName: UserDefaults.argumentDomain)

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)   // no Dock icon, no menu bar, never activated
    let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated], reason: "Cetchup extractor check")
    let harness = Harness(options: options)
    DispatchQueue.main.asyncAfter(deadline: .now() + options.timeout) {
        eprint("error: timed out after \(Int(options.timeout))s (page load plus extractor)")
        finish(3)
    }
    Task { @MainActor in
        let code = await harness.run()
        ProcessInfo.processInfo.endActivity(activity)
        finish(code)
    }
    app.run()
}
