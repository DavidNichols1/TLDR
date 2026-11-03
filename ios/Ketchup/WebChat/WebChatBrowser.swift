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
//  JavaScript world, and it checks the page again itself.
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
        if let suffix = source.userAgentSuffix { config.applicationNameForUserAgent = suffix }
        webView = WKWebView(frame: .zero, configuration: config)
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
                MainActor.assumeIsolated { self?.url = web.url }
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
        guard let url, source.allows(url), let name = source.outlineScript else { throw WebChatError.readerMissing }
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

/// The browser's web view, as a SwiftUI view.
struct WebChatWebView: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
