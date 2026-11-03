//
//  ChatsListView.swift
//  Ketchup
//
//  The inbox (my_chats): newest activity first, unread badges, new chat,
//  join with a code, pull to refresh, sign out.
//

import SwiftUI

struct ChatsListView: View {
    @Environment(AppModel.self) private var app

    @State private var path: [UUID] = []
    @State private var showNew = false
    @State private var showJoin = false
    @State private var newName = ""
    @State private var joinCode = ""
    @State private var busy = false
    @State private var error: String?
    /// The big serif title has scrolled under the bar, so the bar shows a small one.
    @State private var titleTucked = false

    @ScaledMetric(relativeTo: .headline) private var monogramSize: CGFloat = 48

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    header
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
            }
            .background(Theme.cream)
            .overlay { emptyState }
            .refreshable { await app.refreshChats() }
            .onScrollGeometryChange(for: Bool.self) { geo in
                geo.contentOffset.y + geo.contentInsets.top > 52
            } action: { _, tucked in
                titleTucked = tucked
            }
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
                NewChatSheet(name: $newName) {
                    showNew = false
                    Task { await create() }
                }
            }
            .sheet(isPresented: $showJoin) {
                JoinChatSheet(code: $joinCode) {
                    showJoin = false
                    Task { await join() }
                }
            }
            .alert("Something went wrong", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(error ?? "")
            }
        }
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
        ToolbarItem(placement: .principal) {
            Text("Chats")
                .font(.serif(.headline))
                .foregroundStyle(Theme.ink)
                .opacity(titleTucked ? 1 : 0)
                .motion(Motion.fade, value: titleTucked)
                .accessibilityHidden(!titleTucked)
        }
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                if let me = app.me {
                    Text("Signed in as \(me.displayName)")
                }
                Button(role: .destructive) {
                    Task { await app.signOut() }
                } label: {
                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            } label: {
                profileLabel
            }
        }
        InstagramToolbarItem()  // experimental, not released: ios/Ketchup/Instagram/
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button { showNew = true } label: { Label("New chat", systemImage: "square.and.pencil") }
                Button { showJoin = true } label: { Label("Join with code", systemImage: "number") }
            } label: {
                if busy { ProgressView() } else { Image(systemName: "plus").foregroundStyle(Theme.ink) }
            }
            .disabled(busy)
            .accessibilityLabel("New chat or join")
        }
    }

    /// My initials in my color, where a generic person icon used to be.
    @ViewBuilder
    private var profileLabel: some View {
        if let me = app.me {
            Text(Theme.initials(me.displayName))
                .font(.system(.subheadline, design: .serif, weight: .bold))
                .foregroundStyle(Theme.personColor(name: me.displayName))
                .accessibilityLabel("Profile, \(me.displayName)")
        } else {
            Image(systemName: "person")
                .foregroundStyle(Theme.ink)
                .accessibilityLabel("Profile")
        }
    }

    // MARK: Empty, loading, offline

    @ViewBuilder
    private var emptyState: some View {
        if !app.chatsLoaded && app.chats.isEmpty {
            if let notice = app.notice {
                EmptyCounter(title: "Couldn't load your chats", message: notice) {
                    Button("Try again") { Task { await app.refreshChats() } }
                        .buttonStyle(.outline(.compact))
                }
            } else {
                ProgressView()
                    .tint(Theme.inkSoft)
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
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        newName = ""
        guard !name.isEmpty else { return }
        busy = true
        defer { busy = false }
        do {
            let id = try await KetchupAPI.createChat(name: String(name.prefix(50)))
            await app.refreshChats()
            path = [id]
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func join() async {
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
