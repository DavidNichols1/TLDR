//
//  InstagramModels.swift
//  Ketchup
//
//  EXPERIMENTAL, NOT RELEASED. What InstagramThreadReader.js reads off an
//  Instagram DM thread, and how catch-up-text's refs (indexes into the
//  messages the app sent) fit the CatchUp model Ketchup's own chats use.
//  None of this is ever written to disk.
//

import Foundation

/// One message as the reader script saw it on the page.
struct IGMessage: Decodable, Equatable {
    let sender: String
    let text: String
    let isMe: Bool
    /// ISO 8601: the last time Instagram printed above this message (approximate).
    let at: String?
}

/// A DM thread read off the page. Held in memory for one catch-up only.
struct IGThread: Equatable {
    let title: String
    let isGroup: Bool
    let messages: [IGMessage]
    /// Instagram had nothing older to load; otherwise this is the newest part.
    let reachedStart: Bool
    /// More messages were loaded than the reader keeps (it keeps the newest).
    let truncated: Bool

    var displayTitle: String { title.isEmpty ? "Instagram chat" : title }
}

/// The reader script's JSON.
struct IGReaderResult: Decodable {
    /// Counts only: safe to log.
    struct Stats: Decodable {
        let root: String
        let scrolls: Int
        let reachedStart: Bool
        let found: Int
        let ms: Int
    }

    let ok: Bool
    let error: String?
    let title: String?
    let isGroup: Bool?
    let messages: [IGMessage]?
    let truncated: Bool?
    let stats: Stats?
}

/// A finished catch-up, for the result sheet.
struct IGCatchUpResult: Identifiable {
    let id = UUID()
    let thread: IGThread
    let brief: CatchUp
    let latencyMs: Int?
}

/// catch-up-text cites messages by their index in the request. The CatchUp
/// model holds refs as UUIDs (for Ketchup's own messages), so each index
/// travels as a fixed UUID whose last 12 hex digits are the index.
enum IGRef {
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
                    out[key] = list.compactMap { ($0 as? NSNumber)?.intValue }.map { id($0).uuidString }
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

enum InstagramError: LocalizedError {
    case notAThread
    case readerMissing
    case unreadable
    case nothingFound

    var errorDescription: String? {
        switch self {
        case .notAThread:    return "Open a chat first, then tap Catch me up."
        case .readerMissing: return "This build is missing the Instagram reader."
        case .unreadable:    return "Couldn't read this chat. Scroll to the newest message and try again."
        case .nothingFound:  return "Couldn't find any messages on this page. Scroll to the newest message and try again."
        }
    }

    /// A readable sentence for anything that goes wrong on the way.
    static func message(for error: Error) -> String {
        if let url = error as? URLError {
            switch url.code {
            case .timedOut: return "Muse Spark took too long. Try again."
            case .notConnectedToInternet, .networkConnectionLost: return "You're offline. Reconnect and try again."
            default: return "Couldn't reach Muse Spark. Try again."
            }
        }
        if error is DecodingError { return "Muse Spark sent back something unexpected. Try again." }
        if case APIError.server(let raw) = error {
            if raw.lowercased().hasPrefix("request failed (50") { return "Muse Spark is busy right now. Try again in a moment." }
            return raw
        }
        if let known = error as? InstagramError { return known.errorDescription ?? "Something went wrong." }
        if (error as NSError).domain == "WKErrorDomain" { return InstagramError.unreadable.errorDescription! }
        return error.localizedDescription
    }
}
