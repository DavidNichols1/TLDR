//
//  WebChatSource.swift
//  Ketchup
//
//  EXPERIMENTAL, NOT RELEASED. A chat app whose own website Ketchup opens
//  in a web view, and reads one open thread from when the user asks, for
//  the same Muse Spark catch-up as Ketchup's own chats (edge function
//  catch-up-text). Instagram is the one that works. Snapchat is listed so
//  the pager has its page, but Snapchat for Web won't run in a phone's web
//  view (it sends phones to the app store), and Ketchup doesn't fake a
//  computer to get around that.
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
    /// anywhere else open in Safari.
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
    /// Whose terms say no to reading it automatically, for the intro card.
    let owner: String
    /// Why the site can't run here, when it can't. The tab says so instead.
    let unavailable: String?
    /// Synthetic test threads for DEBUG builds.
    let fixtures: [Fixture]

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
        owner: "Meta",
        unavailable: nil,
        fixtures: [
            Fixture(title: "Test thread", file: "ig-thread-fixture",
                    url: URL(string: "https://www.instagram.com/direct/t/ketchup-test-fixture/")!),
            Fixture(title: "Test thread, real page structure", file: "ig-thread-fixture-virtual",
                    url: URL(string: "https://www.instagram.com/direct/t/ketchup-test-fixture/")!),
        ])

    /// Checked Nov 3, 2026: with a phone's user agent web.snapchat.com says
    /// to use a computer; with a desktop one and desktop content mode it
    /// still lands on the mobile "Download Snapchat" page, because the page
    /// sees a touch screen and a phone-wide window. Getting past that would
    /// take a script injected into every Snapchat page, sign-in included,
    /// which Ketchup doesn't do.
    static let snapchat = WebChatSource(
        id: "snapchat",
        name: "Snapchat",
        startURL: URL(string: "https://web.snapchat.com")!,
        domains: ["snapchat.com"],
        threadHost: "web.snapchat.com",
        threadPath: "^/[^/]+",
        readerScript: "",
        outlineScript: nil,
        userAgentSuffix: nil,
        owner: "Snap",
        unavailable: "Snapchat for Web only runs on a computer. On a phone it sends you to the Snapchat app, and Ketchup won't pretend to be a computer to get around that.",
        fixtures: [])

    static let all: [WebChatSource] = [.instagram, .snapchat]
}
