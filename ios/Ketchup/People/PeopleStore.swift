//
//  PeopleStore.swift
//  Ketchup
//
//  Your people and the people you've blocked, for the whole app: the People
//  and Blocked people lists, the marks on profiles and in Chat info, and
//  Add / Remove, Block / Unblock. The server is what counts (contacts, and
//  RLS on messages, migration 0007); this keeps the lists for the screens
//  and does what the phone has to do at once.
//

import Foundation
import Observation

@Observable
final class PeopleStore {
    static let shared = PeopleStore()

    private(set) var blocked: [BlockedPerson] = []
    private(set) var loaded = false
    private(set) var contacts: [Contact] = []
    private(set) var contactsLoaded = false
    /// Whose list this is, so the next person to sign in starts empty.
    @ObservationIgnored private var owner: UUID?

    func isBlocked(_ id: UUID) -> Bool { blocked.contains { $0.id == id } }
    func isContact(_ id: UUID) -> Bool { contacts.contains { $0.id == id } }

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
        // Blocking takes them out of your people (block_person does too).
        contacts.removeAll { $0.id == person.id }
    }

    func unblock(_ id: UUID) async throws {
        startFresh()
        if !Previewing.isOn { try await KetchupAPI.unblock(id) }
        blocked.removeAll { $0.id == id }
    }

    // MARK: Your people

    /// Fetches your people once per signed-in person, or again with `force`.
    func loadContacts(force: Bool = false) async {
        startFresh()
        guard force || !contactsLoaded, !Previewing.isOn else { return }
        guard let list = try? await KetchupAPI.myContacts() else { return }
        contacts = list
        contactsLoaded = true
    }

    func addContact(_ person: Person, sharedChats: Int = 1) async throws {
        startFresh()
        if !Previewing.isOn { try await KetchupAPI.addContact(person.id) }
        guard !isContact(person.id) else { return }
        contacts.append(Contact(id: person.id, displayName: person.name, avatarPath: person.avatarPath,
                                addedAt: .now, sharedChats: sharedChats))
        contacts.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    func removeContact(_ id: UUID) async throws {
        startFresh()
        if !Previewing.isOn { try await KetchupAPI.removeContact(id) }
        contacts.removeAll { $0.id == id }
    }

    private func startFresh() {
        let current = Supabase.shared.userId
        guard current != owner else { return }
        owner = current
        blocked = []
        loaded = false
        contacts = []
        contactsLoaded = false
    }

    #if DEBUG
    /// A preview's lists, as if they had loaded.
    func preview(blocked: [BlockedPerson], contacts: [Contact] = []) {
        owner = Supabase.shared.userId
        self.blocked = blocked
        loaded = true
        self.contacts = contacts
        contactsLoaded = true
    }
    #endif
}
