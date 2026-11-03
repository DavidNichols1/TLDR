//
//  WebChatSource.swift
//  Ketchup
//
//  EXPERIMENTAL, NOT RELEASED. A chat app whose own website Ketchup opens
//  in a web view, and reads one open thread from when the user asks, for
//  the same Muse Spark catch-up as Ketchup's own chats (edge function
//  catch-up-text). Instagram runs its phone page; Snapchat only runs its
//  computer version, so it gets the desktop page, laid out wide and scaled
//  to fit, in app-bound mode.
//

import Foundation

struct WebChatSource: Identifiable, Hashable {
    /// Also catch-up-text's `source`.
    let id: String
    /// "Instagram".
    let name: String
    /// Where the web view starts: the site's own inbox.
    let startURL: URL
    /// The web view stays on these sites (and their subdomains); links
    /// anywhere else open in Safari. In app-bound mode they must also be in
    /// Info.plist's WKAppBoundDomains.
    let domains: [String]
    /// A single chat thread, where the catch-up button shows: this host or
    /// a subdomain, and a path matching `threadPath` (a regular expression).
    let threadHost: String
    let threadPath: String
    /// Bundle `.js` files run on tap, never injected into a page: the
    /// reader, and the DEBUG outline tool.
    let readerScript: String
    let outlineScript: String?
    /// Appended to WebKit's user agent, so the site serves its normal
    /// mobile page.
    let userAgentSuffix: String?
    /// For a site that only runs on a computer: WebKit asks for the desktop
    /// page with this user agent, and the page is laid out this wide, then
    /// scaled down to fit. A view transform, nothing in the page.
    let desktop: Desktop?
    /// Keeps the web view to Info.plist's WKAppBoundDomains, the only way
    /// WebKit lets a site run its service worker.
    let appBound: Bool
    /// Whose terms say no to reading it automatically, for the intro card.
    let owner: String
    /// One more line for the intro card, when the site needs explaining.
    let note: String?
    /// Synthetic test threads for DEBUG builds.
    let fixtures: [Fixture]

    struct Desktop: Hashable {
        let userAgent: String
        /// Points.
        let width: Double
    }

    /// A test page in the app bundle, shown at a thread URL so the button
    /// and the reader behave as they would on the real site.
    struct Fixture: Hashable {
        let title: String
        let file: String
        let url: URL
    }

    /// "Instagram chat", for a thread with no title.
    var fallbackTitle: String { "\(name) chat" }

    func isThread(_ url: URL?) -> Bool {
        guard let url, url.scheme == "https", Self.url(url, isOn: threadHost) else { return false }
        return url.path.range(of: threadPath, options: .regularExpression) != nil
    }

    func allows(_ url: URL) -> Bool {
        url.scheme == "https" && domains.contains { Self.url(url, isOn: $0) }
    }

    static func url(_ url: URL, isOn domain: String) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == domain || host.hasSuffix("." + domain)
    }

    static func == (a: Self, b: Self) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension WebChatSource {
    static let instagram = WebChatSource(
        id: "instagram",
        name: "Instagram",
        startURL: URL(string: "https://www.instagram.com/direct/inbox/")!,
        domains: ["instagram.com", "facebook.com", "meta.com", "fbsbx.com", "fbcdn.net", "cdninstagram.com"],
        threadHost: "instagram.com",
        threadPath: "^/direct/t/[^/]+",
        readerScript: "InstagramThreadReader",
        outlineScript: "InstagramPageOutline",
        userAgentSuffix: "Version/26.0 Mobile/15E148 Safari/604.1",
        desktop: nil,
        appBound: false,
        owner: "Meta",
        note: nil,
        fixtures: [
            Fixture(title: "Test thread", file: "ig-thread-fixture",
                    url: URL(string: "https://www.instagram.com/direct/t/ketchup-test-fixture/")!),
            Fixture(title: "Test thread, real page structure", file: "ig-thread-fixture-virtual",
                    url: URL(string: "https://www.instagram.com/direct/t/ketchup-test-fixture/")!),
        ])

    /// Snapchat for Web, checked Nov 3, 2026. On a phone it sends you to
    /// "Download Snapchat", even with a desktop user agent; with the page
    /// laid out wide too, it serves its computer version. Signed in, its chat
    /// app then needs a service worker, so it runs in app-bound mode.
    static let snapchat = WebChatSource(
        id: "snapchat",
        name: "Snapchat",
        startURL: URL(string: "https://www.snapchat.com/web")!,
        domains: ["snapchat.com", "snap.com"],
        threadHost: "www.snapchat.com",
        threadPath: "^/web/[^/]+",
        readerScript: "SnapchatThreadReader",
        outlineScript: "SnapchatPageOutline",
        userAgentSuffix: nil,
        desktop: Desktop(userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/27.0 Safari/605.1.15",
                         width: 1024),
        appBound: true,
        owner: "Snap",
        note: "Snapchat only runs its computer version here, so the page is shrunk to fit. Pinch to zoom.",
        fixtures: [
            Fixture(title: "Test chat", file: "snap-thread-fixture",
                    url: URL(string: "https://www.snapchat.com/web/ketchup-test-fixture")!),
        ])

    static let all: [WebChatSource] = [.instagram, .snapchat]
}
