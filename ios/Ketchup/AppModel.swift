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
    /// Something that changed at once and then didn't go through on the
    /// server (leaving a chat, a new name). The inbox and Settings say so.
    var problem: String?

    /// Offline preview mode (DEBUG only, see Debug/PreviewData.swift): stands
    /// in for a session, and every server call below becomes a no-op.
    private(set) var previewUser: UUID?

    var isSignedIn: Bool { session != nil || previewUser != nil }
    var myId: UUID? { previewUser ?? session?.userId }

    init() {
        Supabase.shared.onSessionChange = { [weak self] session in
            let before = self?.session?.userId
            self?.session = session
            if session == nil {
                self?.me = nil
                self?.chats = []
                self?.chatsLoaded = false
                // Signing out leaves nothing of theirs on the phone.
                DeviceStore.shared.wipe()
                RemoteImages.shared.clear()
            } else if session?.userId != before {
                self?.restoreFromDevice()
            }
        }
        DeviceStore.shared.tidy()
        restoreFromDevice()
    }

    // MARK: Kept on the phone

    /// Opens on the inbox and name this phone kept from last time
    /// (DeviceStore), while refreshChats() asks the server.
    private func restoreFromDevice() {
        guard let kept = DeviceStore.shared.inbox() else { return }
        me = kept.me
        chats = kept.chats
        chatsLoaded = true
    }

    /// Only once the inbox has loaded, so a first launch never keeps an empty one.
    private func keepOnDevice() {
        guard previewUser == nil, chatsLoaded else { return }
        DeviceStore.shared.saveInbox(InboxSnapshot(me: me, chats: chats))
    }

    func signOut() async {
        guard previewUser == nil else { return }
        await Supabase.shared.signOut()
    }

    func loadMe() async {
        guard isSignedIn, previewUser == nil else { return }
        nameConfirmed = UserDefaults.standard.bool(forKey: nameKey)
        // Offline, the name kept on the phone stays.
        if let profile = try? await KetchupAPI.myProfile() {
            me = profile
            keepOnDevice()
        }
    }

    // MARK: Display name

    /// Sign-up gives everyone their email's local part as a name
    /// (handle_new_user). Until they confirm or change it once, the app asks.
    private(set) var nameConfirmed = true

    private var nameKey: String { "nameConfirmed-\(myId?.uuidString ?? "")" }

    /// The name the server picked on sign-up, for prefilling the name step.
    var defaultName: String {
        if previewUser != nil { return me?.displayName ?? "" }
        let local = session?.email.split(separator: "@").first.map(String.init) ?? ""
        return String(local.trimmingCharacters(in: .whitespaces).prefix(30))
    }

    var needsName: Bool {
        guard let me, !nameConfirmed else { return false }
        return me.displayName == defaultName
    }

    func confirmName() {
        if previewUser == nil { UserDefaults.standard.set(true, forKey: nameKey) }
        nameConfirmed = true
    }

    func rename(to name: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...30).contains(trimmed.count) else { throw APIError.server("Names are 1–30 characters.") }
        if previewUser == nil { try await KetchupAPI.setDisplayName(trimmed) }
        me?.displayName = trimmed
        confirmName()
        keepOnDevice()
    }

    /// A new or removed profile photo, once the server has it
    /// (Photos/ProfilePhotos.swift does the saving).
    func setAvatarPath(_ path: String?) {
        me?.avatarPath = path
        keepOnDevice()
    }

    func refreshChats() async {
        guard isSignedIn else { return }
        guard previewUser == nil else {
            #if DEBUG
            if previewHoldsLoading { return }
            #endif
            chatsLoaded = true
            return
        }
        let user = myId
        do {
            // A chat you're leaving stays gone while the server catches up.
            let fresh = try await KetchupAPI.myChats().filter { !leaving.contains($0.id) }
            guard myId == user else { return }  // signed out meanwhile
            let changed = fresh != chats
            chats = fresh
            chatsLoaded = true
            if changed { keepOnDevice() }
            // A chat you've left (or were removed from) doesn't stay on the phone.
            DeviceStore.shared.keepThreads(Set(fresh.map(\.id)))
        } catch {
            if !chatsLoaded { notice = error.localizedDescription }
        }
    }

    func chat(_ id: UUID) -> ChatSummary? { chats.first { $0.id == id } }

    // MARK: At once, the server following

    /// Chats you've just left, until the server has it.
    @ObservationIgnored private var leaving: Set<UUID> = []

    /// Leaves at once: the chat is out of the inbox and off the phone now,
    /// and the server follows. If it says no, the chat comes back and
    /// `problem` says so.
    func leave(_ chat: ChatSummary) async {
        leaving.insert(chat.id)
        chats.removeAll { $0.id == chat.id }
        keepOnDevice()
        DeviceStore.shared.keepThreads(Set(chats.map(\.id)))
        do {
            try await serverLeave(chat.id)
            leaving.remove(chat.id)
        } catch {
            leaving.remove(chat.id)
            problem = "Couldn't leave \(chat.name), so you're still in it. \(error.localizedDescription)"
            if previewUser == nil {
                await refreshChats()
            } else {
                chats.insert(chat, at: 0)
            }
        }
    }

    /// Settings: your new name shows everywhere at once and the server
    /// follows. If it says no, the old name comes back (unless you've changed
    /// it again since) and `problem` says so. The first-run name step waits
    /// for the server instead: rename(to:).
    func renameNow(to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...30).contains(trimmed.count), let before = me?.displayName, trimmed != before else { return }
        me?.displayName = trimmed
        keepOnDevice()
        Task {
            do {
                try await serverRename(trimmed)
                confirmName()
            } catch {
                if me?.displayName == trimmed {
                    me?.displayName = before
                    keepOnDevice()
                }
                problem = "Couldn't change your name to \(trimmed), so it's still \(before). \(error.localizedDescription)"
            }
        }
    }

    /// The two server calls. An offline preview pretends, and with
    /// `-serverRefuses YES` says no after a moment, to show the way back.
    private func serverLeave(_ chat: UUID) async throws {
        if previewUser == nil { return try await KetchupAPI.leaveChat(chat) }
        #if DEBUG
        try await previewAnswer()
        #endif
    }

    private func serverRename(_ name: String) async throws {
        if previewUser == nil { return try await KetchupAPI.setDisplayName(name) }
        #if DEBUG
        try await previewAnswer()
        #endif
    }

    /// Clears the unread badge locally right away (the server follows).
    func markReadLocally(_ id: UUID) {
        guard let i = chats.firstIndex(where: { $0.id == id }) else { return }
        chats[i].unreadCount = 0
        chats[i].lastReadAt = Date()
        keepOnDevice()
    }

    #if DEBUG
    /// Offline preview mode: signed in as `previewUser` with no session, so
    /// nothing here touches the network or the Keychain session.
    private init(previewUser: UUID) {
        self.previewUser = previewUser
        self.session = nil
    }

    /// An inbox preview that never finishes loading (`-screen inbox-loading`).
    @ObservationIgnored private var previewHoldsLoading = false

    private func previewAnswer() async throws {
        guard UserDefaults.standard.bool(forKey: "serverRefuses") else { return }
        try await Task.sleep(for: .seconds(1.2))
        throw APIError.server("The server said no (a preview).")
    }

    /// A signed-in app with a fixed name and inbox, for `-screen` previews.
    /// `loading` keeps the inbox waiting on its first answer.
    static func preview(me: UUID, name: String, chats: [ChatSummary], loading: Bool = false) -> AppModel {
        let app = AppModel(previewUser: me)
        app.me = Profile(id: me, displayName: name)
        app.chats = chats
        app.chatsLoaded = !loading
        app.previewHoldsLoading = loading
        return app
    }
    #endif
}
