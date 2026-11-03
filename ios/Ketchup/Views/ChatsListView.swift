//
//  ChatsListView.swift
//  Ketchup
//
//  The inbox (my_chats): newest activity first, unread badges, new chat,
//  join with a code, pull to refresh, Settings (top left). The first page of
//  HomePager, whose switcher sits in the middle of this top bar.
//

import SwiftUI

struct ChatsListView: View {
    @Environment(AppModel.self) private var app
    @Environment(HomePagerState.self) private var pager: HomePagerState?

    @State private var path: [UUID] = []
    @State private var showNew = false
    @State private var showJoin = false
    @State private var showSettings = false
    @State private var showInvite = false
    @State private var settingsExit: SettingsExit?
    @State private var newName = ""
    /// Your people picked in New chat, added straight in (People/).
    @State private var newPeople: Set<UUID> = []
    @State private var joinCode = ""
    @State private var busy = false
    @State private var error: String?

    @ScaledMetric(relativeTo: .headline) private var monogramSize: CGFloat = 48

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    header
                    if waitingForChats {
                        InboxSkeleton()
                    }
                    ForEach(app.chats) { chat in
                        NavigationLink(value: chat.id) {
                            ChatListRow(chat: chat)
                        }
                        .buttonStyle(PressableButtonStyle(scale: 0.98))
                        if chat.id != app.chats.last?.id {
                            Rectangle()
                                .fill(Theme.rule)
                                .frame(height: 1)
                                .padding(.leading, 20 + monogramSize + 14)
                        }
                    }
                }
                .padding(.bottom, 24)
                .motion(Motion.fade, value: app.chatsLoaded)
            }
            .background(Theme.cream)
            .overlay { emptyState }
            .refreshable { await app.refreshChats() }
            .navigationTitle("Chats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .navigationDestination(for: UUID.self) { id in
                if let chat = app.chat(id), let me = app.myId {
                    ChatView(chat: chat, myId: me)
                        .id(id)
                } else {
                    Text("Chat not found")
                        .font(.serif(.title3))
                        .foregroundStyle(Theme.inkSoft)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.cream)
                }
            }
            .sheet(isPresented: $showNew) {
                NewChatSheet(name: $newName, people: PeopleStore.shared.contacts.map(\.person), picked: $newPeople) {
                    showNew = false
                    Task { await create() }
                }
                .task { await PeopleStore.shared.loadContacts() }
            }
            .sheet(isPresented: $showJoin) {
                JoinChatSheet(code: $joinCode) {
                    showJoin = false
                    Task { await join() }
                }
            }
            .sheet(isPresented: $showInvite) { InviteSheet() }
            // Signing out waits for the sheet to go, so it isn't left over sign-in.
            .sheet(isPresented: $showSettings, onDismiss: {
                guard let exit = settingsExit else { return }
                settingsExit = nil
                Task { await app.leave(exit) }
            }) {
                SettingsView { exit in
                    if showSettings {
                        settingsExit = exit
                        showSettings = false
                    } else {
                        // Already closed (a delete finished after the sheet
                        // went): nothing will dismiss it again, so leave now.
                        Task { await app.leave(exit) }
                    }
                }
            }
            .alert("Something went wrong", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(error ?? "")
            }
        }
        #if DEBUG
        // `-screen settings-sheet` opens Settings over the inbox (PeoplePreviewScreen).
        .onAppear { if UserDefaults.standard.bool(forKey: "KetchupOpenSettings") { showSettings = true } }
        #endif
        // Keep the inbox fresh while it's on screen (badges, previews).
        .task {
            while !Task.isCancelled {
                if path.isEmpty { await app.refreshChats() }
                try? await Task.sleep(for: .seconds(15))
            }
        }
        .onChange(of: path) { _, new in
            if new.isEmpty { Task { await app.refreshChats() } }
        }
        // In a chat, horizontal swipes are the chat's: the pager stays put.
        .onChange(of: path.isEmpty, initial: true) { _, atInbox in
            pager?.locked = !atInbox
        }
    }

    /// "Chats" in New York, with how much is waiting over it.
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Kicker(summary)
            Text("Chats")
                .font(.serif(.largeTitle))
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    private var summary: String {
        let unread = app.chats.reduce(0) { $0 + $1.unreadCount }
        if app.chats.isEmpty { return app.me.map { "Hi, \($0.displayName)" } ?? "Inbox" }
        if unread == 0 { return "All caught up" }
        return unread == 1 ? "1 new message" : "\(unread) new messages"
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        // The middle of the bar stays empty (no "Chats" title): HomePager's
        // switcher sits there.
        ToolbarItem(placement: .principal) {
            Color.clear.frame(width: 1, height: 1).accessibilityHidden(true)
        }
        ToolbarItem(placement: .topBarLeading) {
            Button { showSettings = true } label: { profileLabel }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button { showNew = true } label: { Label("New chat", systemImage: "square.and.pencil") }
                Button { showJoin = true } label: { Label("Join with code", systemImage: "number") }
                Button { showInvite = true } label: { Label("Invite friends", systemImage: "paperplane") }
            } label: {
                if busy { ProgressView() } else { Image(systemName: "plus").foregroundStyle(Theme.ink) }
            }
            .disabled(busy)
            .accessibilityLabel("New chat or join")
        }
    }

    /// My photo, or my initials in my color, where a generic person icon used to be.
    @ViewBuilder
    private var profileLabel: some View {
        if let me = app.me {
            Avatar(name: me.displayName, path: me.avatarPath, size: 30)
                .accessibilityHidden(false)
                .accessibilityLabel("Settings, \(me.displayName)")
        } else {
            Image(systemName: "person")
                .foregroundStyle(Theme.ink)
                .accessibilityLabel("Settings")
        }
    }

    // MARK: Empty, loading, offline

    /// First launch only: after that the inbox the phone kept shows at once.
    private var waitingForChats: Bool {
        !app.chatsLoaded && app.chats.isEmpty && app.notice == nil
    }

    @ViewBuilder
    private var emptyState: some View {
        if !app.chatsLoaded && app.chats.isEmpty {
            if let notice = app.notice {
                EmptyCounter(title: "Couldn't load your chats", message: notice) {
                    Button("Try again") { Task { await app.refreshChats() } }
                        .buttonStyle(.outline(.compact))
                }
            }
        } else if app.chats.isEmpty {
            EmptyCounter(title: "Nothing on the counter yet",
                         message: "Start a group chat, or join one with an invite code from a friend.") {
                VStack(spacing: 10) {
                    Button("Start a chat") { showNew = true }
                        .buttonStyle(.ketchup)
                    Button("Join with code") { showJoin = true }
                        .buttonStyle(.outline)
                }
                .padding(.top, 8)
            }
        }
    }

    // MARK: Actions

    private func create() async {
        guard !busy else { return }  // a second tap while it's still going
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let people = Array(newPeople)
        newName = ""
        newPeople = []
        guard !name.isEmpty else { return }
        busy = true
        defer { busy = false }
        do {
            let id = people.isEmpty
                ? try await KetchupAPI.createChat(name: String(name.prefix(50)))
                : try await KetchupAPI.createChat(name: String(name.prefix(50)), with: people)
            await app.refreshChats()
            path = [id]
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func join() async {
        guard !busy else { return }
        let code = joinCode.uppercased().filter { $0.isLetter || $0.isNumber }
        joinCode = ""
        guard code.count == 6 else {
            error = "Invite codes are 6 letters and numbers."
            return
        }
        busy = true
        defer { busy = false }
        do {
            guard let id = try await KetchupAPI.joinChat(code: code) else {
                error = "No chat has the code \(code). Check it and try again."
                return
            }
            await app.refreshChats()
            path = [id]
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// The empty inbox, and the inbox that couldn't load: a big drop, a serif
/// line, a sentence, and what to do about it.
private struct EmptyCounter<Actions: View>: View {
    let title: String
    let message: String
    @ViewBuilder let actions: Actions

    @ScaledMetric(relativeTo: .largeTitle) private var dropSize: CGFloat = 84

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                KetchupDrop().fill(Theme.ketchup)
                DropShine().fill(Theme.onKetchup.opacity(0.9))
            }
            .frame(width: dropSize, height: dropSize)
            .rotationEffect(.degrees(-8))
            .accessibilityHidden(true)
            .padding(.bottom, 6)

            Text(title)
                .font(.serif(.title2))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(.body)
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
            actions
        }
        .padding(.horizontal, 36)
        .frame(maxWidth: 440)
    }
}
