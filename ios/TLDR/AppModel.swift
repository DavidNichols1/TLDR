//
//  AppModel.swift
//  TLDR
//
//  App-wide state: who is signed in, their name, and the inbox.
//

import SwiftUI
import Observation

@Observable
final class AppModel {

    private(set) var session: AuthSession? = Supabase.shared.session
    private(set) var me: Profile?
    private(set) var chats: [ChatSummary] = []
    private(set) var chatsLoaded = false
    var notice: String?

    var isSignedIn: Bool { session != nil }
    var myId: UUID? { session?.userId }

    init() {
        Supabase.shared.onSessionChange = { [weak self] session in
            self?.session = session
            if session == nil {
                self?.me = nil
                self?.chats = []
                self?.chatsLoaded = false
            }
        }
    }

    func signOut() async {
        await Supabase.shared.signOut()
    }

    func loadMe() async {
        guard isSignedIn else { return }
        me = try? await TLDRAPI.myProfile()
    }

    func rename(to name: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...30).contains(trimmed.count) else { throw APIError.server("Names are 1–30 characters.") }
        try await TLDRAPI.setDisplayName(trimmed)
        me?.displayName = trimmed
    }

    func refreshChats() async {
        guard isSignedIn else { return }
        do {
            chats = try await TLDRAPI.myChats()
            chatsLoaded = true
        } catch {
            if !chatsLoaded { notice = error.localizedDescription }
        }
    }

    func chat(_ id: UUID) -> ChatSummary? { chats.first { $0.id == id } }

    /// Clears the unread badge locally right away (the server follows).
    func markReadLocally(_ id: UUID) {
        guard let i = chats.firstIndex(where: { $0.id == id }) else { return }
        chats[i].unreadCount = 0
        chats[i].lastReadAt = Date()
    }
}
