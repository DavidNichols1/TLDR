//
//  WebChatFollow.swift
//  Ketchup
//
//  EXPERIMENTAL, NOT RELEASED. "Until I stop scrolling" on a web chat: the
//  person scrolls the site's page and Ketchup only reads, never scrolling
//  itself (WebChatBrowser.follow). This is what the page's panel watches
//  while it runs, and the two ways out of it.
//

import Foundation

/// One "Until I stop scrolling", as it goes.
@Observable
final class WebFollow {
    /// Messages read so far, for the panel.
    var found = 0
    /// "Catch me up now": finish with what's been read.
    @ObservationIgnored private(set) var finishNow = false
    /// "Stop", or the person left: nothing is sent and nothing is kept.
    @ObservationIgnored private(set) var stopped = false
    /// Keeps reading until Stop or Catch me up now, with no timers. Only
    /// the DEBUG preview sets it, so the panel holds still for screenshots.
    @ObservationIgnored var holds = false

    func catchUpNow() { finishNow = true }
    func stop() { stopped = true }

    /// The same numbers as Android's ThreadReader (FOLLOW_QUIET_MS and the rest).
    static let quiet: Duration = .seconds(3)     // done this long after the last new message
    static let idle: Duration = .seconds(5)      // or this long after the start, if none came
    static let longest: Duration = .seconds(180)
    static let poll: Duration = .milliseconds(250)
    /// What catch-up-text covers.
    static let most = 600
}

/// The reader's answer to a look while following: how many messages it
/// holds so far, or why it can't go on ("gone": the page was replaced;
/// "thread_changed"; "read_failed"). Counts and fixed words only.
struct FollowLook {
    let found: Int
    let error: String?

    init(_ value: Any?) throws {
        guard let json = value as? String,
              let object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else {
            throw WebChatError.unreadable
        }
        if object["ok"] as? Bool == true {
            found = object["found"] as? Int ?? 0
            error = nil
        } else {
            found = 0
            error = object["error"] as? String ?? "read_failed"
        }
    }
}
