//
//  ProfileView.swift
//  Ketchup
//
//  Someone's profile: their photo and name, the chats you share, and what
//  you can do about them (Block or Unblock, Report). It's pushed from a
//  member in Chat info, or opens as a sheet from a sender's name or photo
//  in the thread (ProfileSheet).
//

import SwiftUI

struct ProfileView: View {
    let person: Person
    /// The chat it was opened from: shared for sure, shown before the server
    /// answers (and if it can't).
    var chat: ChatSummary?
    /// After a block (true) or an unblock (false), so an open chat can drop
    /// or bring back their messages at once.
    var onBlockChange: (Bool) -> Void

    @Environment(AppModel.self) private var app
    @State private var shared: [ChatSummary]?
    @State private var confirmBlock = false
    @State private var working = false
    @State private var reporting = false
    @State private var error: String?

    @ScaledMetric(relativeTo: .largeTitle) private var avatarSize: CGFloat = 64

    private var store: PeopleStore { .shared }
    private var blocked: Bool { store.isBlocked(person.id) }

    init(person: Person, in chat: ChatSummary? = nil, onBlockChange: @escaping (Bool) -> Void = { _ in }) {
        self.person = person
        self.chat = chat
        self.onBlockChange = onBlockChange
    }

    #if DEBUG
    /// Offline previews: the chats you share, without asking the server.
    var previewShared: [ChatSummary]?

    init(person: Person, previewShared: [ChatSummary]) {
        self.init(person: person)
        self.previewShared = previewShared
    }
    #endif

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                header
                sharedChats
                actions
                if let error {
                    FormError(text: error)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 36)
        }
        .background(Theme.cream)
        .navigationTitle(person.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // The big header names them; the bar keeps just its buttons.
            ToolbarItem(placement: .principal) {
                Color.clear.frame(width: 1, height: 1).accessibilityHidden(true)
            }
        }
        .navigationDestination(isPresented: $reporting) {
            ReportView(target: .person(person)) { onBlockChange(true) }
        }
        .confirmationDialog("Block \(person.name)?", isPresented: $confirmBlock, titleVisibility: .visible) {
            Button("Block \(person.name)", role: .destructive) { Task { await setBlocked(true) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You won't see their messages in any chat, and \(Theme.modelName) won't read them for your catch-ups. They won't be told, and they'll still see yours.")
        }
        .motion(value: blocked)
        .task {
            await store.load()
            await loadShared()
        }
    }

    // MARK: Header

    /// How many chats you share, their name in New York, a Blocked stamp if
    /// you've blocked them, and their photo.
    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Kicker(sharedLine)
                Text(person.name)
                    .font(.serif(.largeTitle))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .accessibilityAddTraits(.isHeader)
                if blocked {
                    Stamp("Blocked", color: Theme.ketchupText)
                        .padding(.top, 4)
                        .transition(.opacity)
                }
            }
            Spacer(minLength: 0)
            Avatar(name: person.name, path: person.avatarPath, size: avatarSize)
        }
        .padding(.top, 6)
        .accessibilityElement(children: .combine)
    }

    private var sharedLine: String {
        guard let shared else { return "Profile" }
        switch shared.count {
        case 0: return "No chats together"
        case 1: return "In 1 chat with you"
        default: return "In \(shared.count) chats with you"
        }
    }

    // MARK: Chats you share

    @ViewBuilder
    private var sharedChats: some View {
        if let shared, !shared.isEmpty {
            SettingsSection("Chats you share") {
                ForEach(shared) { chat in
                    SettingsRow(chat.name, systemImage: "bubble.left.and.bubble.right",
                                value: chat.memberCount == 1 ? "1 person" : "\(chat.memberCount) people")
                }
            }
        }
    }

    // MARK: Block or report

    private var actions: some View {
        SettingsSection("Block or report", footer: blocked
            ? "You don't see their messages in any chat, and \(Theme.modelName) leaves them out of your catch-ups. Unblock to see them again."
            : "Blocking is quiet. They aren't told and still see your messages; theirs disappear for you everywhere, catch-ups included.") {
            contactSlot
            if blocked {
                Button {
                    Task { await setBlocked(false) }
                } label: {
                    SettingsRow("Unblock \(person.name)", systemImage: "hand.raised.slash") {
                        if working { ProgressView().tint(Theme.inkSoft) }
                    }
                }
                .buttonStyle(.pressable)
                .disabled(working)
            } else {
                Button {
                    confirmBlock = true
                } label: {
                    SettingsRow("Block \(person.name)", systemImage: "hand.raised", destructive: true) {
                        if working { ProgressView().tint(Theme.ketchupText) }
                    }
                }
                .buttonStyle(.pressable)
                .disabled(working)
            }
            Button {
                reporting = true
            } label: {
                SettingsRow("Report \(person.name)", systemImage: "flag", chevron: true)
            }
            .buttonStyle(.pressable)
        }
    }

    /// SLOT (People session, slice 3): "Add to your people" or "Remove".
    @ViewBuilder private var contactSlot: some View {}

    // MARK: Actions

    private func loadShared() async {
        #if DEBUG
        if let previewShared {
            shared = previewShared
            return
        }
        #endif
        if shared == nil, let chat { shared = [chat] }
        // Offline: keep what's known rather than say there are none.
        guard let ids = try? await KetchupAPI.sharedChats(with: person.id) else { return }
        shared = app.chats.filter { ids.contains($0.id) }
    }

    private func setBlocked(_ block: Bool) async {
        guard !working else { return }
        working = true
        error = nil
        defer { working = false }
        do {
            if block {
                try await store.block(person)
            } else {
                try await store.unblock(person.id)
            }
            onBlockChange(block)
            // Unread counts and inbox lines leave them out (or bring them back).
            await app.refreshChats()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// A profile from the thread, in a sheet of its own with Done.
struct ProfileSheet: View {
    let person: Person
    var chat: ChatSummary?
    var onBlockChange: (Bool) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ProfileView(person: person, in: chat, onBlockChange: onBlockChange)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .presentationBackground(Theme.cream)
    }
}

/// What the thread opens about a person: their profile, or a report.
enum PeopleSheet: Identifiable {
    case profile(Person)
    case report(ReportTarget)

    var id: String {
        switch self {
        case .profile(let person): "profile-\(person.id)"
        case .report(let target): "report-\(target.id)"
        }
    }
}

/// A sender's name over the first bubble of their run (ChatBubble and
/// PhotoBubble). With `onTap` it's a button that opens their profile.
struct SenderName: View {
    let name: String
    let color: Color
    var onTap: (() -> Void)?

    var body: some View {
        let label = Text(name)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.leading, 12)
        if let onTap {
            Button(action: onTap) {
                label.contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens their profile")
        } else {
            label
        }
    }
}
