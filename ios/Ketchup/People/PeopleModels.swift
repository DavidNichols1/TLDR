//
//  PeopleModels.swift
//  Ketchup
//
//  The people side's small types: someone whose profile you can open,
//  someone you've blocked (my_blocks()), and what a report is about and why
//  (the reports table, migration 0007).
//

import Foundation

/// Someone in your chats: enough to open their profile.
struct Person: Identifiable, Hashable {
    let id: UUID
    var name: String
    var avatarPath: String?

    init(id: UUID, name: String, avatarPath: String? = nil) {
        self.id = id
        self.name = name
        self.avatarPath = avatarPath
    }

    init(_ member: Member) {
        self.init(id: member.userId, name: member.name, avatarPath: member.profile?.avatarPath)
    }
}

/// A row of `my_blocks()`: everyone you've blocked, newest first.
struct BlockedPerson: Codable, Identifiable, Equatable {
    let id: UUID
    var displayName: String
    var avatarPath: String?
    var blockedAt: Date

    var person: Person { Person(id: id, name: displayName, avatarPath: avatarPath) }

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case avatarPath = "avatar_path"
        case blockedAt = "blocked_at"
    }
}

/// A row of `my_contacts()`: one of your people, by name.
struct Contact: Codable, Identifiable, Equatable {
    let id: UUID
    var displayName: String
    var avatarPath: String?
    var addedAt: Date
    /// Chats you're both in right now.
    var sharedChats: Int

    var person: Person { Person(id: id, name: displayName, avatarPath: avatarPath) }

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case avatarPath = "avatar_path"
        case addedAt = "added_at"
        case sharedChats = "shared_chats"
    }
}

/// Why something's reported. The raw values are the reports table's
/// `reason` check.
enum ReportReason: String, CaseIterable, Identifiable {
    case spam, harassment, hate, threats, sexual, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .spam: "Spam"
        case .harassment: "Harassment or bullying"
        case .hate: "Hate"
        case .threats: "Threats or violence"
        case .sexual: "Sexual content"
        case .other: "Something else"
        }
    }
}

/// What a report is about: one message (the person who sent it comes along),
/// or a person.
enum ReportTarget: Identifiable, Hashable {
    case message(Message, from: Person)
    case person(Person)

    var id: String {
        switch self {
        case .message(let m, _): "message-\(m.id)"
        case .person(let p): "person-\(p.id)"
        }
    }

    /// Whoever's reported: the sender of a message, or the person.
    var person: Person {
        switch self {
        case .message(_, let from): from
        case .person(let p): p
        }
    }

    static func == (a: Self, b: Self) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Offline previews (`-screen`, DEBUG only): the people screens act on the
/// phone alone and never call the server. Always false in Release.
enum Previewing {
    static var isOn: Bool {
        #if DEBUG
        PreviewData.isActive
        #else
        false
        #endif
    }
}
