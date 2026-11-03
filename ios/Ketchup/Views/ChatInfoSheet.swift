//
//  ChatInfoSheet.swift
//  Ketchup
//
//  Members, the invite code (share or copy), and Leave chat.
//

import SwiftUI

struct ChatInfoSheet: View {
    let model: ChatModel
    let onLeft: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var confirmLeave = false
    @State private var leaving = false
    @State private var copied = false
    @State private var error: String?

    @ScaledMetric(relativeTo: .body) private var monogramSize: CGFloat = 36

    private var code: String { model.chat.inviteCode }
    private var peopleCount: Int { model.members.isEmpty ? model.chat.memberCount : model.members.count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    invite
                    people
                    leaveRow
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(Theme.cream)
            .navigationTitle(model.chat.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(model.chat.name)
                        .font(.serif(.headline))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Leave “\(model.chat.name)”?", isPresented: $confirmLeave, titleVisibility: .visible) {
                Button("Leave chat", role: .destructive) { Task { await leave() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You'll stop getting its messages. You can rejoin with the invite code.")
            }
            .task { await model.loadMembers() }
        }
        .presentationBackground(Theme.cream)
    }

    // MARK: Invite code

    /// The code on an order ticket, people counted on the stub, then Share
    /// (the one ketchup button) and Copy.
    private var invite: some View {
        VStack(alignment: .leading, spacing: 14) {
            Ticket(notchAt: 0.74) {
                VStack(alignment: .leading, spacing: 6) {
                    Kicker("Invite code")
                    Text(code)
                        .font(.mono(.largeTitle, weight: .semibold))
                        .tracking(5)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .textSelection(.enabled)
                        .accessibilityLabel(code.map(String.init).joined(separator: " "))
                }
            } stub: {
                VStack(spacing: 2) {
                    Text("\(peopleCount)")
                        .font(.mono(.title2, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Kicker(peopleCount == 1 ? "Person" : "People")
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
            }

            Text("Anyone with this code can join and read the whole chat.")
                .font(.footnote)
                .foregroundStyle(Theme.inkSoft)

            HStack(spacing: 10) {
                ShareLink(item: "Join “\(model.chat.name)” on Ketchup with code \(code)") {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.ketchup)

                Button {
                    UIPasteboard.general.string = code
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.outline)
                .sensoryFeedback(.success, trigger: copied) { _, now in now }
            }
        }
    }

    // MARK: People

    private var people: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("People", count: model.members.isEmpty ? nil : model.members.count)
            VStack(spacing: 0) {
                ForEach(model.members) { member in
                    HStack(spacing: 12) {
                        Monogram(name: member.name, size: monogramSize)
                        Text(member.name)
                            .font(.body)
                            .foregroundStyle(Theme.ink)
                        if member.userId == model.myId {
                            Kicker("You")
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 10)
                    .accessibilityElement(children: .combine)
                    if member.id != model.members.last?.id {
                        Rectangle()
                            .fill(Theme.rule)
                            .frame(height: 1)
                            .padding(.leading, monogramSize + 12)
                    }
                }
            }
            .paperCard(padding: 14)
        }
    }

    // MARK: Leave

    private var leaveRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(role: .destructive) {
                confirmLeave = true
            } label: {
                HStack {
                    Label("Leave chat", systemImage: "rectangle.portrait.and.arrow.right")
                    Spacer(minLength: 0)
                    if leaving { ProgressView().tint(Theme.ketchupText) }
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.ketchupText)
                .paperCard(padding: 16)
            }
            .buttonStyle(.pressable)
            .disabled(leaving)

            if let error {
                FormError(text: error)
            }
        }
    }

    private func leave() async {
        leaving = true
        defer { leaving = false }
        do {
            try await KetchupAPI.leaveChat(model.chat.id)
            onLeft()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
