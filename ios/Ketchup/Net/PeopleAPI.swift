//
//  PeopleAPI.swift
//  Ketchup
//
//  Server calls for your account and the people around you (migration
//  0007). Like the rest of KetchupAPI, they run as the signed-in member, so
//  Row Level Security decides what each one may touch.
//

import Foundation

extension KetchupAPI {

    // MARK: Account

    /// Deletes the signed-in account and everything it wrote, for good, through
    /// the delete-account edge function: the rows first (`delete_account()`:
    /// profile, memberships, messages, catch-ups, and friends' saved catch-ups
    /// that read those messages), then the photos they uploaded. If it fails,
    /// nothing has changed.
    static func deleteAccount() async throws {
        _ = try await Supabase.shared.function("delete-account", [:])
    }

    // MARK: Block

    /// One way and silent: from the next read, the server leaves their
    /// messages out for you everywhere (RLS on messages), catch-ups included.
    static func block(_ person: UUID) async throws {
        _ = try await Supabase.shared.rpc("block_person", ["p_user": person.uuidString])
    }

    static func unblock(_ person: UUID) async throws {
        _ = try await Supabase.shared.rpc("unblock_person", ["p_user": person.uuidString])
    }

    /// Everyone you've blocked, newest first.
    static func myBlocks() async throws -> [BlockedPerson] {
        let data = try await Supabase.shared.rpc("my_blocks")
        return try JSON.decoder.decode([BlockedPerson].self, from: data)
    }

    /// The chats you share with someone. chat_members only shows the
    /// caller's own chats, so asking for theirs answers exactly that.
    static func sharedChats(with person: UUID) async throws -> [UUID] {
        struct Row: Decodable { let chatId: UUID; enum CodingKeys: String, CodingKey { case chatId = "chat_id" } }
        let data = try await Supabase.shared.rest("GET", "/rest/v1/chat_members",
                                                  query: [.init(name: "user_id", value: "eq.\(person.uuidString)"),
                                                          .init(name: "select", value: "chat_id")])
        return try JSON.decoder.decode([Row].self, from: data).map(\.chatId)
    }

    // MARK: Report

    /// Files a report. The server fills in who's reported and copies the
    /// message (fill_report); nobody can read it back through the API. `id`
    /// is the client's, so report-alert can be asked to email about it.
    static func report(id: UUID, _ target: ReportTarget, reason: ReportReason, note: String?) async throws {
        var row: [String: Any] = ["id": id.uuidString, "reason": reason.rawValue]
        switch target {
        case .message(let message, _): row["message_id"] = message.id.uuidString
        case .person(let person): row["reported_user"] = person.id.uuidString
        }
        if let note, !note.isEmpty { row["note"] = String(note.prefix(500)) }
        try await Supabase.shared.rest("POST", "/rest/v1/reports",
                                       body: JSONSerialization.data(withJSONObject: row),
                                       prefer: "return=minimal")
    }

    /// Asks the report-alert edge function to email David about a new report.
    /// Best effort: the report is already saved, and without the function
    /// (or its secrets) nothing is lost.
    static func alertReport(_ id: UUID) async {
        _ = try? await Supabase.shared.function("report-alert", ["report_id": id.uuidString])
    }
}
