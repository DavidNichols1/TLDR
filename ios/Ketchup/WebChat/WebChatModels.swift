//
//  WebChatModels.swift
//  Ketchup
//
//  EXPERIMENTAL, NOT RELEASED. What a source's reader script reads off a
//  chat thread, and how catch-up-text's refs (indexes into the messages
//  the app sent) fit the CatchUp model Ketchup's own chats use. None of
//  this is ever written to disk.
//

import Foundation

/// One message as the reader saw it on the page.
struct WebMessage: Decodable, Equatable {
    let sender: String
    let text: String
    let isMe: Bool
    /// ISO 8601: the last time the page printed above this message (approximate).
    let at: String?
}

/// A thread read off the page. Held in memory for one catch-up only.
struct WebThread: Equatable {
    let source: WebChatSource
    let title: String
    let isGroup: Bool
    let messages: [WebMessage]
    /// The site had nothing older to load; otherwise this is the newest part.
    let reachedStart: Bool
    /// More messages were loaded than the reader keeps (it keeps the newest).
    let truncated: Bool
    /// How the read went, in counts only (sent along so the server log can show it).
    let stats: WebReaderResult.Stats?

    var displayTitle: String { title.isEmpty ? source.fallbackTitle : title }

    func message(_ ref: UUID) -> WebMessage? {
        WebRef.index(ref).flatMap { messages.indices.contains($0) ? messages[$0] : nil }
    }
}

/// A reader script's JSON.
struct WebReaderResult: Decodable {
    /// Counts only: safe to log.
    struct Stats: Decodable, Equatable {
        let root: String
        let stop: String?
        let scrolls: Int
        let steps: Int?
        let gaps: Int?
        let reachedStart: Bool
        let placeholders: Int?
        let rows: Int?
        let units: Int?
        let found: Int
        let skipped: Int?
        let empty: Int?
        let dupes: Int?
        let ms: Int

        /// For the request body: numbers and fixed words only, never page text.
        var report: [String: Any] {
            var out: [String: Any] = ["root": root, "scrolls": scrolls, "reachedStart": reachedStart, "found": found, "ms": ms]
            if let stop { out["stop"] = stop }
            for (key, value) in [("steps", steps), ("gaps", gaps), ("placeholders", placeholders), ("rows", rows),
                                 ("units", units), ("skipped", skipped), ("empty", empty), ("dupes", dupes)] {
                if let value { out[key] = value }
            }
            return out
        }
    }

    let ok: Bool
    let error: String?
    /// The reader's own word for what broke ("TypeError", "no-list"), never content.
    let detail: String?
    let title: String?
    let isGroup: Bool?
    let messages: [WebMessage]?
    let truncated: Bool?
    let stats: Stats?
}

/// catch-up-text cites messages by their index in the request. The CatchUp
/// model holds refs as UUIDs (for Ketchup's own messages), so each index
/// travels as a fixed UUID whose last 12 hex digits are the index.
nonisolated enum WebRef {
    private static let prefix = "00000000-0000-0000-0000-"

    static func id(_ index: Int) -> UUID {
        UUID(uuidString: prefix + String(format: "%012lX", index))!
    }

    static func index(_ id: UUID) -> Int? {
        let s = id.uuidString
        guard s.hasPrefix(prefix) else { return nil }
        return Int(s.dropFirst(prefix.count), radix: 16)
    }

    /// Swaps every `"refs": [Int]` in the server's JSON for UUID strings.
    static func rewrite(_ value: Any) -> Any {
        if let object = value as? [String: Any] {
            var out: [String: Any] = [:]
            for (key, v) in object {
                if key == "refs", let list = v as? [Any] {
                    out[key] = list.compactMap { ($0 as? NSNumber)?.intValue }
                        .filter { (0..<(1 << 40)).contains($0) }
                        .map { id($0).uuidString }
                } else {
                    out[key] = rewrite(v)
                }
            }
            return out
        }
        if let list = value as? [Any] { return list.map(rewrite) }
        return value
    }
}

enum WebChatError: LocalizedError {
    case notAThread
    case readerMissing
    case unreadable
    case nothingFound

    var errorDescription: String? {
        switch self {
        case .notAThread:    return "Open a chat first, then tap Catch me up."
        case .readerMissing: return "This build is missing the reader for this app."
        case .unreadable:    return "Couldn't read this chat. Scroll to the newest message and try again."
        case .nothingFound:  return "Couldn't find any messages on this page. Scroll to the newest message and try again."
        }
    }

    /// A readable sentence for anything that goes wrong on the way: the
    /// reader's own errors and the page's, then AIErrors for the rest.
    static func message(for error: Error) -> String {
        if let known = error as? WebChatError { return known.errorDescription ?? "Something went wrong." }
        if (error as NSError).domain == "WKErrorDomain" { return WebChatError.unreadable.errorDescription! }
        return AIErrors.message(for: error)
    }
}
