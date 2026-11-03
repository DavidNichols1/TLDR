//
//  BlockedPeopleView.swift
//  Ketchup
//
//  Settings → Blocked people: everyone you've blocked, newest first, with
//  Unblock. Unblocking brings their messages back in every chat you share.
//

import SwiftUI

struct BlockedPeopleView: View {
    @Environment(AppModel.self) private var app
    @State private var working: UUID?
    @State private var error: String?

    @ScaledMetric(relativeTo: .body) private var avatarSize: CGFloat = 36

    private var store: PeopleStore { .shared }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("They aren't told. You don't see their messages in any chat, and \(Theme.modelName) leaves them out of your catch-ups.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)

                if store.blocked.isEmpty {
                    if store.loaded { nobody } else { ProgressView().tint(Theme.inkSoft).frame(maxWidth: .infinity) }
                } else {
                    list
                }

                if let error {
                    FormError(text: error)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .background(Theme.cream)
        .navigationTitle("Blocked people")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Blocked people")
                    .font(.serif(.headline))
                    .foregroundStyle(Theme.ink)
            }
        }
        .motion(value: store.blocked.map(\.id))
        .task { await store.load(force: true) }
    }

    private var list: some View {
        VStack(spacing: 0) {
            ForEach(store.blocked) { person in
                HStack(spacing: 12) {
                    Avatar(name: person.displayName, path: person.avatarPath, size: avatarSize)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(person.displayName)
                            .font(.body)
                            .foregroundStyle(Theme.ink)
                        Text("Blocked \(person.blockedAt.formatted(.dateTime.month(.abbreviated).day()))")
                            .font(.mono(.caption2))
                            .foregroundStyle(Theme.inkSoft)
                    }
                    Spacer(minLength: 8)
                    Button {
                        Task { await unblock(person) }
                    } label: {
                        ZStack {
                            Text("Unblock").opacity(working == person.id ? 0 : 1)
                            if working == person.id { ProgressView().tint(Theme.ink) }
                        }
                    }
                    .buttonStyle(.outline(.compact))
                    .disabled(working != nil)
                    .accessibilityLabel("Unblock \(person.displayName)")
                }
                .padding(.vertical, 12)
                .transition(.opacity)
                if person.id != store.blocked.last?.id {
                    Rectangle()
                        .fill(Theme.rule)
                        .frame(height: 1)
                        .padding(.leading, avatarSize + 12)
                }
            }
        }
        .paperCard(padding: 14)
    }

    /// Nobody blocked: a quiet card saying where Block lives.
    private var nobody: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No one's blocked")
                .font(.serif(.title3))
                .foregroundStyle(Theme.ink)
            Text("To block someone, tap their name in a chat or in Chat info.")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .paperCard(padding: 18)
    }

    private func unblock(_ person: BlockedPerson) async {
        working = person.id
        error = nil
        defer { working = nil }
        do {
            try await store.unblock(person.id)
            await app.refreshChats()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
