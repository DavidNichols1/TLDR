//
//  Models.swift
//  Ketchup
//

import Foundation

struct Profile: Codable, Identifiable, Equatable {
    let id: UUID
    var displayName: String
    /// Their photo in the avatars bucket (Photos/Avatar.swift), if they set one.
    var avatarPath: String? = nil

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case avatarPath = "avatar_path"
    }
}

/// A row of the inbox (`my_chats()`).
struct ChatSummary: Codable, Identifiable, Equatable, Hashable {
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

struct Member: Codable, Identifiable, Equatable {
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

struct Message: Codable, Identifiable, Equatable {
    let id: UUID
    let chatId: UUID
    let sender: UUID
    /// The text, or a photo's caption (may be empty then).
    let body: String
    let createdAt: Date
    /// A photo in the chat-media bucket and its size in pixels (Photos/ChatPhotos.swift).
    var imagePath: String? = nil
    var imageWidth: Int? = nil
    var imageHeight: Int? = nil
    /// "text", or "joined" for a "Maya joined" line the server writes
    /// (migration 0009). Rows and kept copies from before it have none: text.
    var kind: String? = nil
    /// Client-only: an optimistic bubble not yet confirmed / that failed.
    var pending = false
    var failed = false

    enum CodingKeys: String, CodingKey {
        case id, sender, body, kind
        case chatId = "chat_id"
        case createdAt = "created_at"
        case imagePath = "image_path"
        case imageWidth = "image_width"
        case imageHeight = "image_height"
    }

    init(id: UUID, chatId: UUID, sender: UUID, body: String, createdAt: Date,
         pending: Bool = false, failed: Bool = false,
         imagePath: String? = nil, imageWidth: Int? = nil, imageHeight: Int? = nil, kind: String? = nil) {
        self.id = id; self.chatId = chatId; self.sender = sender; self.body = body
        self.createdAt = createdAt; self.pending = pending; self.failed = failed
        self.imagePath = imagePath; self.imageWidth = imageWidth; self.imageHeight = imageHeight
        self.kind = kind
    }

    /// A "Maya joined" line: drawn small and centered, never counted as unread.
    var isJoin: Bool { kind == "joined" }
}

// MARK: - Muse Spark results (shape set by supabase/functions/_shared/brief.ts)

struct CatchUp: Codable, Equatable {
    struct Item: Codable, Equatable, Hashable { let text: String; let refs: [UUID] }

    struct Plan: Codable, Equatable, Hashable, Identifiable {
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

    struct Question: Codable, Equatable, Hashable {
        let question: String
        let askedBy: String?
        let refs: [UUID]
        enum CodingKeys: String, CodingKey { case question, refs; case askedBy = "asked_by" }
    }

    struct Owe: Codable, Equatable, Hashable {
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

struct ChatAnswer: Codable, Equatable {
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
    /// Its ai_briefs row, new or reused, so the phone keeps it once.
    var briefId: UUID?
    let error: String?

    var untilDate: Date? { until.flatMap(JSON.date(from:)) }

    enum CodingKeys: String, CodingKey {
        case kind, empty, cached, result, model, error, until
        case messageCount = "message_count"
        case latencyMs = "latency_ms"
        case briefId = "brief_id"
    }
}
