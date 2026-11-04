//
//  WebChatBrowser.swift
//  Ketchup
//
//  EXPERIMENTAL, NOT RELEASED. A source's own website in a web view.
//
//  The user signs in on the site's own page. Ketchup never sees, stores or
//  touches their password or cookies: the default (persistent) website data
//  store keeps the sign-in the way Safari would. Nothing is injected into
//  any page. The source's reader script runs only when the user picks how
//  much to catch up on, on a thread page, in Ketchup's own isolated
//  JavaScript world, and it checks the page again itself. A desktop source
//  (Snapchat) gets WebKit's desktop page and a custom user agent, the way
//  Safari's "Request Desktop Website" does it, and app-bound mode.
//

import SwiftUI
import WebKit

@Observable
final class WebChatBrowser {
    let source: WebChatSource
    @ObservationIgnored let webView: WKWebView
    @ObservationIgnored private let policy: WebChatNavigationPolicy
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    private(set) var url: URL?
    private(set) var isLoading = false
    private(set) var canGoBack = false

    /// The catch-up button shows only on a chat thread.
    var isThread: Bool { source.isThread(url) }

    #if DEBUG
    /// The synthetic test thread on screen, if that's what's open (DEBUG
    /// checks compare a read with its ground truth).
    @ObservationIgnored private(set) var fixture: WebChatSource.Fixture?
    #endif

    init(source: WebChatSource) {
        self.source = source
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.limitsNavigationsToAppBoundDomains = source.appBound
        if source.desktop != nil { config.defaultWebpagePreferences.preferredContentMode = .desktop }
        if let suffix = source.userAgentSuffix { config.applicationNameForUserAgent = suffix }
        webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = source.desktop?.userAgent
        policy = WebChatNavigationPolicy(source: source)
        webView.navigationDelegate = policy
        webView.uiDelegate = policy
        webView.allowsBackForwardNavigationGestures = true
        #if DEBUG
        webView.isInspectable = true  // Safari's Develop menu, for tuning a reader
        #endif
        // Sites change pages with pushState, which only KVO on `url` sees.
        observations = [
            webView.observe(\.url, options: [.initial, .new]) { [weak self] web, _ in
                MainActor.assumeIsolated {
                    self?.url = web.url
                    #if DEBUG
                    if let self, let url = web.url { print("[\(self.source.id)] page \(Self.redacted(url))") }
                    #endif
                }
            },
            webView.observe(\.isLoading, options: [.initial, .new]) { [weak self] web, _ in
                MainActor.assumeIsolated { self?.isLoading = web.isLoading }
            },
            webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] web, _ in
                MainActor.assumeIsolated { self?.canGoBack = web.canGoBack }
            },
        ]
    }

    func openStart() {
        #if DEBUG
        fixture = nil
        #endif
        webView.load(URLRequest(url: source.startURL))
    }
    func reload() { webView.reload() }
    func goBack() { webView.goBack() }

    /// Reads the newest `last` messages of the thread on screen: one pick,
    /// one read. It steps up through the thread (the site may load older
    /// messages on the way), then puts the scroll back.
    func readThread(readerName: String, last: Int) async throws -> WebThread {
        guard isThread else { throw WebChatError.notAThread }
        let script = try Self.script(source.readerScript)
        let value: Any?
        do {
            value = try await webView.callAsyncJavaScript(
                script,
                // Older messages come in batches of about 20: a bigger pick may need a few more.
                arguments: ["maxMessages": last, "maxScrolls": min(10, 2 + last / 20), "readerName": readerName, "debug": false],
                in: nil,
                contentWorld: .defaultClient)
        } catch {
            #if DEBUG
            let ns = error as NSError  // codes only, never content
            print("[\(source.id)] reader didn't run: \(ns.domain) \(ns.code)")
            #endif
            throw error
        }
        return try thread(from: value) { s in  // counts only, never content
            "read \(s.found) messages, \(s.scrolls) loads, stop \(s.stop ?? "?"), via \(s.root), \(s.ms) ms"
        }
    }

    /// The thread in a reader's JSON, or why there isn't one. `log` says how
    /// the read went, in counts only, for the DEBUG console.
    private func thread(from value: Any?, log: (WebReaderResult.Stats) -> String) throws -> WebThread {
        guard let json = value as? String else { throw WebChatError.unreadable }
        let result = try JSONDecoder().decode(WebReaderResult.self, from: Data(json.utf8))
        guard result.ok, let messages = result.messages else {
            #if DEBUG
            print("[\(source.id)] reader said \(result.error ?? "?") (\(result.detail ?? "no detail"))")
            #endif
            throw result.error == "not_a_thread" ? WebChatError.notAThread : WebChatError.unreadable
        }
        #if DEBUG
        if let s = result.stats { print("[\(source.id)] \(log(s))") }
        #endif
        guard !messages.isEmpty else { throw WebChatError.nothingFound }
        return WebThread(source: source, title: result.title ?? "", isGroup: result.isGroup ?? false, messages: messages,
                         reachedStart: result.stats?.reachedStart ?? false, truncated: result.truncated ?? false,
                         stats: result.stats)
    }

    // MARK: Until I stop scrolling

    /// "Until I stop scrolling": a read that never scrolls. The reader reads
    /// what's on screen, then looks again every quarter second while the
    /// person scrolls and keeps what they scrolled past, laid together with
    /// a Last N read's stitching and dedupe. It's done at the first of:
    /// about 3 seconds after the last new message turned up, 5 seconds
    /// after the start if none did, 600 messages, or 3 minutes (the same
    /// rules as Android's ThreadReader.follow). Then it's the same thread a
    /// Last N read returns. Nil when it stopped instead: Stop, the tab or
    /// app left, another page or thread. Then nothing goes anywhere, and
    /// what the reader held is dropped from the page.
    func follow(_ follow: WebFollow, readerName: String) async throws -> WebThread? {
        guard isThread, let thread = url else { throw WebChatError.notAThread }
        let script = try Self.script(source.readerScript)
        let clock = ContinuousClock()
        let started = clock.now
        var lastNew: ContinuousClock.Instant?
        var looks = 0
        func step(_ name: String, stop: String = "enough") async throws -> Any? {
            looks += 1
            return try await webView.callAsyncJavaScript(
                script,
                arguments: ["follow": name, "stop": stop, "maxMessages": WebFollow.most, "maxScrolls": 0,
                            "readerName": readerName, "debug": false],
                in: nil,
                contentWorld: .defaultClient)
        }
        /// Still the thread it started on (sites change pages with pushState).
        func same() -> Bool { url?.host == thread.host && url?.path == thread.path }
        /// Stops it: the reader forgets what it read, if the page is still there.
        func drop() async -> WebThread? {
            if same() { _ = try? await step("stop") }
            #if DEBUG
            print("[\(source.id)] follow stopped after \(looks) looks, nothing sent")
            #endif
            return nil
        }

        do {
            var reply = try FollowLook(try await step("start"))
            // catch-up-text's word for why it ended, and the console's plainer one.
            var stop = "enough", why = "quiet"
            while true {
                if follow.stopped || !same() { return await drop() }
                if let error = reply.error { return try await lost(error, drop: drop) }
                follow.found = min(reply.found, WebFollow.most)
                let now = clock.now
                if follow.finishNow || reply.found >= WebFollow.most {
                    why = follow.finishNow ? "now" : "most"
                    break
                }
                if now - started >= WebFollow.longest {
                    (stop, why) = ("budget", "budget")
                    break
                }
                if !follow.holds {
                    // They never scrolled: what's on screen is the read.
                    if lastNew == nil, now - started >= WebFollow.idle {
                        why = "idle"
                        break
                    }
                    // They stopped scrolling.
                    if let lastNew, now - lastNew >= WebFollow.quiet { break }
                }
                try await Task.sleep(for: WebFollow.poll)
                if follow.stopped || !same() { return await drop() }
                let before = reply.found
                reply = try FollowLook(try await step("look"))
                if reply.error == nil, reply.found > before { lastNew = clock.now }
            }
            let value = try await step("finish", stop: stop)
            return try self.thread(from: value) { [why] s in  // counts only, never content
                "follow read \(s.found) messages, \(s.steps ?? looks) looks, stop \(s.stop ?? "?") (\(why)), gaps \(s.gaps ?? 0), dupes \(s.dupes ?? 0), \(s.ms) ms"
            }
        } catch is CancellationError {
            return await drop()
        } catch {
            #if DEBUG
            let ns = error as NSError  // codes only, never content
            if !(error is WebChatError) && !(error is DecodingError) { print("[\(source.id)] follow didn't run: \(ns.domain) \(ns.code)") }
            #endif
            // The page went away under it (a reload, another site): that's leaving, not a failure.
            if !same() { return await drop() }
            _ = try? await step("stop")
            throw error
        }
    }

    /// A look that came back without a count: the page was replaced or the
    /// thread changed (the reader already let go), or it couldn't read.
    private func lost(_ error: String, drop: () async -> WebThread?) async throws -> WebThread? {
        switch error {
        case "gone", "thread_changed": return await drop()
        case "not_a_thread": throw WebChatError.notAThread
        default:
            #if DEBUG
            print("[\(source.id)] follow reader said \(error)")
            #endif
            throw WebChatError.unreadable
        }
    }

    private static func script(_ name: String) throws -> String {
        guard !name.isEmpty, let file = Bundle.main.url(forResource: name, withExtension: "js"),
              let script = try? String(contentsOf: file, encoding: .utf8) else { throw WebChatError.readerMissing }
        return script
    }

    #if DEBUG
    /// Host and path for the console, with ids and the query left out: any
    /// path piece that isn't a plain word becomes `:id`.
    static func redacted(_ url: URL) -> String {
        let parts = url.path.split(separator: "/").map { piece in
            piece.range(of: "^([a-z][a-z-]{0,24}|v[0-9])$", options: .regularExpression) != nil ? String(piece) : ":id"
        }
        return (url.host ?? url.scheme ?? "?") + "/" + parts.joined(separator: "/")
    }

    /// Test page only: a synthetic thread from the app bundle, shown at a
    /// thread URL so the button and the reader behave as they would on the
    /// real site. It makes no network requests.
    func open(_ fixture: WebChatSource.Fixture) {
        guard let file = Bundle.main.url(forResource: fixture.file, withExtension: "html"),
              let html = try? String(contentsOf: file, encoding: .utf8) else { return }
        self.fixture = fixture
        webView.loadHTMLString(html, baseURL: fixture.url)
    }

    /// For tuning a reader against the real site: a redacted outline of
    /// the page (structure, styles, positions; text only as lengths), saved
    /// to the app's temporary folder. Returns the file.
    func savePageOutline() async throws -> URL {
        // Thread pages only, like the reader: never a sign-in page.
        guard isThread, let name = source.outlineScript else { throw WebChatError.notAThread }
        let outline = try await webView.callAsyncJavaScript(try Self.script(name), arguments: [:], in: nil,
                                                            contentWorld: .defaultClient) as? String ?? ""
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("\(source.id)-outline.txt")
        try outline.write(to: out, atomically: true, encoding: .utf8)
        return out
    }
    #endif
}

/// Keeps the web view on the source's sites. A link to anywhere else
/// (something a friend sent) opens in Safari instead, and "open in the
/// app" links do nothing.
final class WebChatNavigationPolicy: NSObject, WKNavigationDelegate, WKUIDelegate {
    private let source: WebChatSource

    init(source: WebChatSource) {
        self.source = source
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = action.request.url else { return .cancel }
        // Frames inside the page (sign-in checks, embeds) load as the site wants.
        if action.targetFrame?.isMainFrame == false || url.scheme == "about" || url.scheme == "blob" { return .allow }
        if source.allows(url) { return .allow }
        if url.scheme == "https" || url.scheme == "http" { await UIApplication.shared.open(url) }
        return .cancel
    }

    /// Links that ask for a new window (target="_blank").
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let url = action.request.url else { return nil }
        if source.allows(url) {
            webView.load(action.request)
        } else if url.scheme == "https" || url.scheme == "http" {
            UIApplication.shared.open(url)
        }
        return nil
    }
}

/// The browser's web view, as a SwiftUI view. With a `layoutWidth` wider
/// than the screen, the page is laid out that wide and scaled down to fit:
/// the site gets a genuinely wide window, and since it's a view transform,
/// touches and pinch zoom still land where they look.
struct WebChatWebView: UIViewRepresentable {
    let webView: WKWebView
    var layoutWidth: Double? = nil

    func makeUIView(context: Context) -> Host { Host(webView: webView, layoutWidth: layoutWidth) }
    func updateUIView(_ uiView: Host, context: Context) {}

    final class Host: UIView {
        let webView: WKWebView
        let layoutWidth: Double?

        init(webView: WKWebView, layoutWidth: Double?) {
            self.webView = webView
            self.layoutWidth = layoutWidth
            super.init(frame: .zero)
            clipsToBounds = true
            addSubview(webView)
        }

        required init?(coder: NSCoder) { fatalError("not from a storyboard") }

        override func layoutSubviews() {
            super.layoutSubviews()
            guard let width = layoutWidth.map({ CGFloat($0) }), bounds.width > 0, width > bounds.width else {
                webView.transform = .identity
                webView.frame = bounds
                return
            }
            let scale = bounds.width / width
            webView.bounds = CGRect(x: 0, y: 0, width: width, height: bounds.height / scale)
            webView.center = CGPoint(x: bounds.midX, y: bounds.midY)
            webView.transform = CGAffineTransform(scaleX: scale, y: scale)
        }
    }
}
