//
//  PeopleStore.swift
//  Ketchup
//
//  The people you've blocked, for the whole app: the Blocked people list,
//  the "Blocked" marks, and Block / Unblock. The server is what hides their
//  messages (RLS on messages, migration 0007); this keeps the list for the
//  screens and does what the phone has to do at once.
//

import Foundation
import Observation

@Observable
final class PeopleStore {
    static let shared = PeopleStore()

    private(set) var blocked: [BlockedPerson] = []
    private(set) var loaded = false
    /// Whose list this is, so the next person to sign in starts empty.
    @ObservationIgnored private var owner: UUID?

    func isBlocked(_ id: UUID) -> Bool { blocked.contains { $0.id == id } }

    /// Fetches the list once per signed-in person, or again with `force`.
    func load(force: Bool = false) async {
        startFresh()
        guard force || !loaded, !Previewing.isOn else { return }
        guard let list = try? await KetchupAPI.myBlocks() else { return }
        blocked = list
        loaded = true
    }

    func block(_ person: Person) async throws {
        startFresh()
        if !Previewing.isOn {
            try await KetchupAPI.block(person.id)
            // The phone's copies of chats may hold their messages; let them
            // go, so none shows them again before the server's page lands.
            DeviceStore.shared.keepThreads([])
        }
        if !isBlocked(person.id) {
            blocked.insert(BlockedPerson(id: person.id, displayName: person.name,
                                         avatarPath: person.avatarPath, blockedAt: .now), at: 0)
        }
    }

    func unblock(_ id: UUID) async throws {
        startFresh()
        if !Previewing.isOn { try await KetchupAPI.unblock(id) }
        blocked.removeAll { $0.id == id }
    }

    private func startFresh() {
        let current = Supabase.shared.userId
        guard current != owner else { return }
        owner = current
        blocked = []
        loaded = false
    }

    #if DEBUG
    /// A preview's list, as if it had loaded.
    func preview(blocked: [BlockedPerson]) {
        owner = Supabase.shared.userId
        self.blocked = blocked
        loaded = true
    }
    #endif
}
