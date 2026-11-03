//
//  Models.swift
//  Ketchup
//

import Foundation

struct Profile: Decodable, Identifiable, Equatable {
    let id: UUID
    var displayName: String

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
    }
}

/// A row of the inbox (`my_chats()`).
struct ChatSummary: Decodable, Identifiable, Equatable, Hashable {
    let id: UUID
    var name: String
    var inviteCode: String
    var memberCount: Int
    var createdAt: Date
    var lastMessageAt: Date?
    var lastMessagePreview: String?
    var lastMessageSenderName: String?
    var lastReadAt: Date
    var unreadCount: Int

    enum CodingKeys: String, CodingKey {
        case id, name
        case inviteCode = "invite_code"
        case memberCount = "member_count"
        case createdAt = "created_at"
        case lastMessageAt = "last_message_at"
        case lastMessagePreview = "last_message_preview"
        case lastMessageSenderName = "last_message_sender_name"
        case lastReadAt = "last_read_at"
        case unreadCount = "unread_count"
    }
}

/// `create_chat` / `join_chat` return a chats row (all nulls for a wrong code).
struct ChatRow: Decodable {
    let id: UUID?
    let name: String?
    let inviteCode: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case inviteCode = "invite_code"
    }
}

struct Member: Decodable, Identifiable, Equatable {
    let userId: UUID
    let joinedAt: Date
    let lastReadAt: Date
    let profile: Profile?

    var id: UUID { userId }
    var name: String { profile?.displayName ?? "Someone" }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case joinedAt = "joined_at"
        case lastReadAt = "last_read_at"
        case profile
    }
}

struct Message: Decodable, Identifiable, Equatable {
    let id: UUID
    let chatId: UUID
    let sender: UUID
    let body: String
    let createdAt: Date
    /// Client-only: an optimistic bubble not yet confirmed / that failed.
    var pending = false
    var failed = false

    enum CodingKeys: String, CodingKey {
        case id, sender, body
        case chatId = "chat_id"
        case createdAt = "created_at"
    }

    init(id: UUID, chatId: UUID, sender: UUID, body: String, createdAt: Date,
         pending: Bool = false, failed: Bool = false) {
        self.id = id; self.chatId = chatId; self.sender = sender; self.body = body
        self.createdAt = createdAt; self.pending = pending; self.failed = failed
    }
}

// MARK: - Muse Spark results (shape set by supabase/functions/_shared/brief.ts)

struct CatchUp: Decodable, Equatable {
    struct Item: Decodable, Equatable, Hashable { let text: String; let refs: [UUID] }

    struct Plan: Decodable, Equatable, Hashable, Identifiable {
        let title: String
        let startsAt: String?
        let endsAt: String?
        let allDay: Bool
        let location: String?
        let status: String
        let who: [String]
        let refs: [UUID]

        var id: String { title + (startsAt ?? "") }
        var confirmed: Bool { status == "confirmed" }
        var start: Date? { startsAt.flatMap(Self.parse) }
        var end: Date? { endsAt.flatMap(Self.parse) }

        /// The model is asked for ISO 8601 with an offset, but the edge
        /// function accepts anything JavaScript can parse, so also take a
        /// bare date ("2026-11-06") or a local time without an offset.
        nonisolated static func parse(_ raw: String) -> Date? {
            if let d = JSON.date(from: raw) { return d }
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = .current
            for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd"] {
                f.dateFormat = format
                if let d = f.date(from: raw) { return d }
            }
            return nil
        }

        enum CodingKeys: String, CodingKey {
            case title, location, status, who, refs
            case startsAt = "starts_at"
            case endsAt = "ends_at"
            case allDay = "all_day"
        }
    }

    struct Question: Decodable, Equatable, Hashable {
        let question: String
        let askedBy: String?
        let refs: [UUID]
        enum CodingKeys: String, CodingKey { case question, refs; case askedBy = "asked_by" }
    }

    struct Owe: Decodable, Equatable, Hashable {
        let who: String
        let owesWhom: String?
        let what: String
        let refs: [UUID]
        enum CodingKeys: String, CodingKey { case who, what, refs; case owesWhom = "owes_whom" }
    }

    let tldr: String
    let highlights: [Item]
    let plans: [Plan]
    let openQuestions: [Question]
    let owes: [Owe]
    let forYou: [Item]

    enum CodingKeys: String, CodingKey {
        case tldr, highlights, plans, owes
        case openQuestions = "open_questions"
        case forYou = "for_you"
    }
}

struct ChatAnswer: Decodable, Equatable {
    let answer: String
    let found: Bool
    let refs: [UUID]
}

/// The edge function's envelope.
struct BriefResponse<Result: Decodable>: Decodable {
    let kind: String?
    let empty: Bool?
    let cached: Bool?
    let result: Result?
    let model: String?
    let messageCount: Int?
    let latencyMs: Int?
    /// Newest message the brief covers (raw timestamp; catch-up moves the
    /// read cursor here, not to "now", so later messages stay unread).
    let until: String?
    let error: String?

    var untilDate: Date? { until.flatMap(JSON.date(from:)) }

    enum CodingKeys: String, CodingKey {
        case kind, empty, cached, result, model, error, until
        case messageCount = "message_count"
        case latencyMs = "latency_ms"
    }
}
