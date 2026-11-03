//
//  TLDRAPI.swift
//  TLDR
//
//  Every server call the app makes. Reads go through PostgREST as the
//  signed-in member, so Row Level Security decides what comes back.
//

import Foundation

enum TLDRAPI {

    private static var client: Supabase { .shared }

    // MARK: Profile

    static func myProfile() async throws -> Profile? {
        guard let me = client.userId else { throw APIError.notSignedIn }
        let data = try await client.rest("GET", "/rest/v1/profiles",
                                         query: [.init(name: "id", value: "eq.\(me.uuidString)"),
                                                 .init(name: "select", value: "id,display_name")])
        return try JSON.decoder.decode([Profile].self, from: data).first
    }

    static func setDisplayName(_ name: String) async throws {
        guard let me = client.userId else { throw APIError.notSignedIn }
        try await client.rest("PATCH", "/rest/v1/profiles",
                              query: [.init(name: "id", value: "eq.\(me.uuidString)")],
                              body: JSONSerialization.data(withJSONObject: ["display_name": name]))
    }

    // MARK: Chats

    static func myChats() async throws -> [ChatSummary] {
        let data = try await client.rpc("my_chats")
        return try JSON.decoder.decode([ChatSummary].self, from: data)
    }

    static func createChat(name: String) async throws -> UUID {
        let data = try await client.rpc("create_chat", ["p_name": name])
        guard let id = try JSON.decoder.decode(ChatRow.self, from: data).id else { throw APIError.badResponse }
        return id
    }

    /// Nil when no chat has that code.
    static func joinChat(code: String) async throws -> UUID? {
        let data = try await client.rpc("join_chat", ["p_code": code])
        // A wrong code comes back as `null` or as a row of nulls.
        return (try? JSON.decoder.decode(ChatRow?.self, from: data))??.id
    }

    static func leaveChat(_ chat: UUID) async throws {
        _ = try await client.rpc("leave_chat", ["p_chat": chat.uuidString])
    }

    static func markRead(_ chat: UUID, at date: Date? = nil) async throws {
        var args: [String: Any] = ["p_chat": chat.uuidString]
        if let date { args["p_at"] = JSON.iso(date) }
        _ = try await client.rpc("mark_read", args)
    }

    static func members(of chat: UUID) async throws -> [Member] {
        let data = try await client.rest("GET", "/rest/v1/chat_members",
                                         query: [.init(name: "chat_id", value: "eq.\(chat.uuidString)"),
                                                 .init(name: "select", value: "user_id,joined_at,last_read_at,profile:profiles(id,display_name)"),
                                                 .init(name: "order", value: "joined_at.asc")])
        return try JSON.decoder.decode([Member].self, from: data)
    }

    // MARK: Messages

    private static let messageColumns = "id,chat_id,sender,body,created_at"

    /// The newest `limit` messages (oldest first), or the page before `before`.
    static func messages(in chat: UUID, before: Date? = nil, limit: Int = 200) async throws -> [Message] {
        var query: [URLQueryItem] = [.init(name: "chat_id", value: "eq.\(chat.uuidString)"),
                                     .init(name: "select", value: messageColumns),
                                     .init(name: "order", value: "created_at.desc"),
                                     .init(name: "limit", value: String(limit))]
        if let before { query.append(.init(name: "created_at", value: "lt.\(JSON.iso(before))")) }
        let data = try await client.rest("GET", "/rest/v1/messages", query: query)
        return try JSON.decoder.decode([Message].self, from: data).reversed()
    }

    /// Everything after `after` (oldest first) — the polling fallback.
    static func messages(in chat: UUID, after: Date) async throws -> [Message] {
        let data = try await client.rest("GET", "/rest/v1/messages",
                                         query: [.init(name: "chat_id", value: "eq.\(chat.uuidString)"),
                                                 .init(name: "created_at", value: "gt.\(JSON.iso(after))"),
                                                 .init(name: "select", value: messageColumns),
                                                 .init(name: "order", value: "created_at.asc"),
                                                 .init(name: "limit", value: "500")])
        return try JSON.decoder.decode([Message].self, from: data)
    }

    /// Inserts with a client-chosen id, so the optimistic bubble and the
    /// Realtime echo are the same message.
    static func send(id: UUID, chat: UUID, body: String) async throws -> Message {
        let payload: [String: Any] = ["id": id.uuidString, "chat_id": chat.uuidString, "body": body]
        let data = try await client.rest("POST", "/rest/v1/messages",
                                         query: [.init(name: "select", value: messageColumns)],
                                         body: JSONSerialization.data(withJSONObject: payload),
                                         prefer: "return=representation")
        guard let row = try JSON.decoder.decode([Message].self, from: data).first else { throw APIError.badResponse }
        return row
    }

    // MARK: Muse Spark

    static func catchUp(chat: UUID) async throws -> BriefResponse<CatchUp> {
        let data = try await client.function("catch-up", ["chat_id": chat.uuidString,
                                                          "mode": "catch_up",
                                                          "time_zone": TimeZone.current.identifier])
        return try JSON.decoder.decode(BriefResponse<CatchUp>.self, from: data)
    }

    static func ask(chat: UUID, question: String) async throws -> BriefResponse<ChatAnswer> {
        let data = try await client.function("catch-up", ["chat_id": chat.uuidString,
                                                          "mode": "ask",
                                                          "question": question,
                                                          "time_zone": TimeZone.current.identifier])
        return try JSON.decoder.decode(BriefResponse<ChatAnswer>.self, from: data)
    }
}
