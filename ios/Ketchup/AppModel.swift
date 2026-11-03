//
//  AppModel.swift
//  Ketchup
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
        nameConfirmed = UserDefaults.standard.bool(forKey: nameKey)
        me = try? await KetchupAPI.myProfile()
    }

    // MARK: Display name

    /// Sign-up gives everyone their email's local part as a name
    /// (handle_new_user). Until they confirm or change it once, the app asks.
    private(set) var nameConfirmed = true

    private var nameKey: String { "nameConfirmed-\(myId?.uuidString ?? "")" }

    /// The name the server picked on sign-up, for prefilling the name step.
    var defaultName: String {
        let local = session?.email.split(separator: "@").first.map(String.init) ?? ""
        return String(local.trimmingCharacters(in: .whitespaces).prefix(30))
    }

    var needsName: Bool {
        guard let me, !nameConfirmed else { return false }
        return me.displayName == defaultName
    }

    func confirmName() {
        UserDefaults.standard.set(true, forKey: nameKey)
        nameConfirmed = true
    }

    func rename(to name: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...30).contains(trimmed.count) else { throw APIError.server("Names are 1–30 characters.") }
        try await KetchupAPI.setDisplayName(trimmed)
        me?.displayName = trimmed
        confirmName()
    }

    func refreshChats() async {
        guard isSignedIn else { return }
        do {
            chats = try await KetchupAPI.myChats()
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
