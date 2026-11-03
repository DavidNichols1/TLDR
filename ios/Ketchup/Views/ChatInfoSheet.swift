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

    private var code: String { model.chat.inviteCode }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 12) {
                        Text(code)
                            .font(.system(size: 40, weight: .bold, design: .monospaced))
                            .tracking(6)
                            .textSelection(.enabled)
                        HStack(spacing: 12) {
                            Button {
                                UIPasteboard.general.string = code
                                copied = true
                            } label: {
                                Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)

                            ShareLink(item: "Join “\(model.chat.name)” on Ketchup with code \(code)") {
                                Label("Share", systemImage: "square.and.arrow.up")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                } header: {
                    Text("Invite code")
                } footer: {
                    Text("Anyone with this code can join and read the whole chat.")
                }

                Section("\(model.members.count) members") {
                    ForEach(model.members) { member in
                        HStack(spacing: 12) {
                            Text(Theme.initials(member.name))
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(Theme.personColor(member.userId), in: Circle())
                            Text(member.name)
                            if member.userId == model.myId {
                                Text("you").foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        confirmLeave = true
                    } label: {
                        HStack {
                            Label("Leave chat", systemImage: "rectangle.portrait.and.arrow.right")
                            if leaving { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(leaving)
                } footer: {
                    if let error { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle(model.chat.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
