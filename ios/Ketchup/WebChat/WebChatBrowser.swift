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

    func openStart() { webView.load(URLRequest(url: source.startURL)) }
    func reload() { webView.reload() }
    func goBack() { webView.goBack() }

    /// Reads the newest `last` messages of the thread on screen: one pick,
    /// one read. It steps up through the thread (the site may load older
    /// messages on the way), then puts the scroll back.
    func readThread(readerName: String, last: Int) async throws -> WebThread {
        guard isThread else { throw WebChatError.notAThread }
        let script = try Self.script(source.readerScript)
        let value = try await webView.callAsyncJavaScript(
            script,
            // Older messages come in batches of about 20: a bigger pick may need a few more.
            arguments: ["maxMessages": last, "maxScrolls": min(10, 2 + last / 20), "readerName": readerName, "debug": false],
            in: nil,
            contentWorld: .defaultClient)
        guard let json = value as? String else { throw WebChatError.unreadable }
        let result = try JSONDecoder().decode(WebReaderResult.self, from: Data(json.utf8))
        guard result.ok, let messages = result.messages else {
            throw result.error == "not_a_thread" ? WebChatError.notAThread : WebChatError.unreadable
        }
        #if DEBUG
        if let s = result.stats {  // counts only, never content
            print("[\(source.id)] read \(s.found) messages, \(s.scrolls) loads, stop \(s.stop ?? "?"), via \(s.root), \(s.ms) ms")
        }
        #endif
        guard !messages.isEmpty else { throw WebChatError.nothingFound }
        return WebThread(source: source, title: result.title ?? "", isGroup: result.isGroup ?? false, messages: messages,
                         reachedStart: result.stats?.reachedStart ?? false, truncated: result.truncated ?? false,
                         stats: result.stats)
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
