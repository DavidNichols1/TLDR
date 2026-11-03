//
//  InstagramBrowser.swift
//  Ketchup
//
//  EXPERIMENTAL, NOT RELEASED. Instagram's own website in a web view.
//
//  The user signs in on Instagram's page. Ketchup never sees, stores or
//  touches their password or cookies: the default (persistent) website data
//  store keeps Instagram's sign-in the way Safari would. Nothing is injected
//  into any page. The one script, InstagramThreadReader.js, runs only when
//  the user taps the catch-up button on a DM thread, in Ketchup's own
//  isolated JavaScript world, and it checks the page again itself.
//

import SwiftUI
import WebKit

@Observable
final class InstagramBrowser {
    static let inbox = URL(string: "https://www.instagram.com/direct/inbox/")!

    @ObservationIgnored let webView: WKWebView
    @ObservationIgnored private let policy = InstagramNavigationPolicy()
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    private(set) var url: URL?
    private(set) var isLoading = false
    private(set) var canGoBack = false

    /// The catch-up button shows only on an Instagram DM thread.
    var isThread: Bool { Self.isThread(url) }

    static func isThread(_ url: URL?) -> Bool {
        guard let url, url.scheme == "https", InstagramNavigationPolicy.isInstagram(url) else { return false }
        let parts = url.path.split(separator: "/")
        return parts.count >= 3 && parts[0] == "direct" && parts[1] == "t"
    }

    init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        // Instagram serves its normal mobile site to Mobile Safari.
        config.applicationNameForUserAgent = "Version/26.0 Mobile/15E148 Safari/604.1"
        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = policy
        webView.uiDelegate = policy
        webView.allowsBackForwardNavigationGestures = true
        // Instagram changes pages with pushState, which only KVO on `url` sees.
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

    func openInbox() { webView.load(URLRequest(url: Self.inbox)) }
    func reload() { webView.reload() }
    func goBack() { webView.goBack() }

    /// Reads the DM thread on screen: one tap, one read. It may scroll the
    /// thread up a few times so Instagram loads older messages, then puts
    /// the scroll back.
    func readThread(readerName: String) async throws -> IGThread {
        guard isThread else { throw InstagramError.notAThread }
        guard let file = Bundle.main.url(forResource: "InstagramThreadReader", withExtension: "js"),
              let script = try? String(contentsOf: file, encoding: .utf8) else { throw InstagramError.readerMissing }
        let value = try await webView.callAsyncJavaScript(
            script,
            arguments: ["maxMessages": 300, "maxScrolls": 6, "readerName": readerName, "debug": false],
            in: nil,
            contentWorld: .defaultClient)
        guard let json = value as? String else { throw InstagramError.unreadable }
        let result = try JSONDecoder().decode(IGReaderResult.self, from: Data(json.utf8))
        guard result.ok, let messages = result.messages else {
            throw result.error == "not_a_thread" ? InstagramError.notAThread : InstagramError.unreadable
        }
        #if DEBUG
        if let s = result.stats {  // counts only, never content
            print("[instagram] read \(s.found) messages, \(s.scrolls) scroll-ups, start reached \(s.reachedStart), via \(s.root), \(s.ms) ms")
        }
        #endif
        guard !messages.isEmpty else { throw InstagramError.nothingFound }
        return IGThread(title: result.title ?? "", isGroup: result.isGroup ?? false, messages: messages,
                        reachedStart: result.stats?.reachedStart ?? false, truncated: result.truncated ?? false)
    }

    #if DEBUG
    /// Test page only: the synthetic thread in Instagram/Fixture/, shown at a
    /// thread URL so the button and the reader behave as they would on the
    /// real site. It makes no network requests.
    func openFixture() {
        guard let file = Bundle.main.url(forResource: "ig-thread-fixture", withExtension: "html"),
              let html = try? String(contentsOf: file, encoding: .utf8) else { return }
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.instagram.com/direct/t/ketchup-test-fixture/"))
    }
    #endif
}

/// Keeps the web view on Instagram and Meta's sign-in pages. A link to
/// anywhere else (something a friend sent) opens in Safari instead, and
/// "open in the Instagram app" links do nothing.
final class InstagramNavigationPolicy: NSObject, WKNavigationDelegate, WKUIDelegate {
    private static let domains = ["instagram.com", "facebook.com", "meta.com", "fbsbx.com", "fbcdn.net", "cdninstagram.com"]

    static func isInstagram(_ url: URL) -> Bool { url.isOn("instagram.com") }

    private static func allowed(_ url: URL) -> Bool {
        url.scheme == "https" && domains.contains { url.isOn($0) }
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = action.request.url else { return .cancel }
        // Frames inside the page (sign-in checks, embeds) load as Instagram wants.
        if action.targetFrame?.isMainFrame == false || url.scheme == "about" || url.scheme == "blob" { return .allow }
        if Self.allowed(url) { return .allow }
        if url.scheme == "https" || url.scheme == "http" { await UIApplication.shared.open(url) }
        return .cancel
    }

    /// Links that ask for a new window (target="_blank").
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let url = action.request.url else { return nil }
        if Self.allowed(url) {
            webView.load(action.request)
        } else if url.scheme == "https" || url.scheme == "http" {
            UIApplication.shared.open(url)
        }
        return nil
    }
}

private extension URL {
    func isOn(_ domain: String) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == domain || host.hasSuffix("." + domain)
    }
}

/// The browser's web view, as a SwiftUI view.
struct InstagramWebView: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
