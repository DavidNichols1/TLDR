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

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(app.chats) { chat in
                    NavigationLink(value: chat.id) {
                        ChatListRow(chat: chat)
                    }
                }
            }
            .listStyle(.plain)
            .overlay { emptyState }
            .refreshable { await app.refreshChats() }
            .navigationTitle("Chats")
            .toolbar { toolbar }
            .navigationDestination(for: UUID.self) { id in
                if let chat = app.chat(id), let me = app.myId {
                    ChatView(chat: chat, myId: me)
                        .id(id)
                } else {
                    ContentUnavailableView("Chat not found", systemImage: "bubble.left.and.exclamationmark.bubble.right")
                }
            }
            .alert("New chat", isPresented: $showNew) {
                TextField("Name, e.g. Friday dinner", text: $newName)
                Button("Create") { Task { await create() } }
                Button("Cancel", role: .cancel) { newName = "" }
            } message: {
                Text("You'll get an invite code to share.")
            }
            .alert("Join a chat", isPresented: $showJoin) {
                TextField("6-character code", text: $joinCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Button("Join") { Task { await join() } }
                Button("Cancel", role: .cancel) { joinCode = "" }
            } message: {
                Text("Ask someone in the chat for its invite code.")
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

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
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
                Image(systemName: "person.crop.circle")
            }
        }
        InstagramToolbarItem()  // experimental, not released: ios/Ketchup/Instagram/
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button { showNew = true } label: { Label("New chat", systemImage: "square.and.pencil") }
                Button { showJoin = true } label: { Label("Join with code", systemImage: "number") }
            } label: {
                if busy { ProgressView() } else { Image(systemName: "plus") }
            }
            .disabled(busy)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if !app.chatsLoaded && app.chats.isEmpty {
            if let notice = app.notice {
                ContentUnavailableView {
                    Label("Couldn't load your chats", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(notice)
                } actions: {
                    Button("Try again") { Task { await app.refreshChats() } }
                }
            } else {
                ProgressView()
            }
        } else if app.chats.isEmpty {
            ContentUnavailableView {
                Label("No chats yet", systemImage: "bubble.left.and.bubble.right")
            } description: {
                Text("Start a group chat or join one with an invite code.")
            } actions: {
                Button("New chat") { showNew = true }
                    .buttonStyle(.borderedProminent)
                Button("Join with code") { showJoin = true }
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
