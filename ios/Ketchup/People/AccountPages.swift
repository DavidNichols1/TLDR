//
//  AccountPages.swift
//  Ketchup
//
//  Settings' pages: change your name, and delete your account (with a
//  plain list of what goes, then one last check).
//

import SwiftUI

// MARK: - Change your name

struct EditNameView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var busy = false
    @State private var error: String?
    @FocusState private var focused: Bool
    @ScaledMetric(relativeTo: .body) private var monogramSize: CGFloat = 30

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var unchanged: Bool { trimmed == app.me?.displayName }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("What do your friends call you?")
                    .font(.serif(.title))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text("They see it in your chats, and \(Theme.modelName) uses it in catch-ups.")
                    .font(.body)
                    .foregroundStyle(Theme.inkSoft)
                    .padding(.top, 10)

                // The monogram follows what you type, as in the name step.
                HStack(spacing: 12) {
                    Monogram(name: trimmed.isEmpty ? "?" : trimmed, size: monogramSize)
                    TextField("Your name", text: $name, prompt: Text("Your name").foregroundStyle(Theme.inkFaint))
                        .textContentType(.givenName)
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit { Task { await save() } }
                }
                .paperField(focused: focused)
                .padding(.top, 24)

                if let error {
                    FormError(text: error)
                        .padding(.top, 12)
                }

                Button {
                    Task { await save() }
                } label: {
                    ZStack {
                        Text("Save name").opacity(busy ? 0 : 1)
                        if busy { ProgressView().tint(Theme.onKetchup) }
                    }
                }
                .buttonStyle(.ketchup)
                .disabled(trimmed.isEmpty || trimmed.count > 30 || unchanged || busy)
                .padding(.top, 14)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.cream)
        .navigationTitle("Your name")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Your name")
                    .font(.serif(.headline))
                    .foregroundStyle(Theme.ink)
            }
        }
        .onAppear {
            name = app.me?.displayName ?? ""
            focused = true
        }
    }

    /// Your name changes everywhere at once and the page closes; if the
    /// server says no, it changes back and Settings says so (AppModel.renameNow).
    private func save() async {
        guard !busy, !unchanged else { return }
        app.renameNow(to: name)
        dismiss()
    }
}

// MARK: - Delete account

struct DeleteAccountView: View {
    /// True while the delete is on its way: no Back, and Settings holds its
    /// Done and swipe-down, so it can't close before the app signs out.
    @Binding var deleting: Bool
    /// Runs once the server has deleted the account: Settings closes and
    /// the app signs out.
    let deleted: () -> Void

    @Environment(AppModel.self) private var app
    @State private var confirm = false
    @State private var error: String?

    init(deleting: Binding<Bool> = .constant(false), deleted: @escaping () -> Void) {
        _deleting = deleting
        self.deleted = deleted
    }

    private var busy: Bool { deleting }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Delete your account")
                        .font(.serif(.largeTitle))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text("This deletes your Cetchup account for good. There's no undo.")
                        .font(.body)
                        .foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 14) {
                    Kicker("What goes")
                    point("text.bubble", "Every message you've sent, in every chat. Your friends won't see them anymore.")
                    point("doc.text", "Your catch-ups, and the ones friends saved that read your messages.")
                    point("person.crop.circle", "Your name, and any chat where you're the only one left.")
                    point("globe", "The Instagram and Snapchat sign-ins in Cetchup on this iPhone.")
                }
                .paperCard(padding: 18)

                VStack(alignment: .leading, spacing: 14) {
                    Kicker("What stays")
                    point("person.2", "Chats with other people. They keep going without you.")
                    point("envelope", "Your email. You can start a new, empty account with it any time.")
                }
                .paperCard(padding: 18)

                if let error {
                    FormError(text: error)
                }

                Button {
                    confirm = true
                } label: {
                    ZStack {
                        Text("Delete my account").opacity(busy ? 0 : 1)
                        if busy { ProgressView().tint(Theme.onKetchup) }
                    }
                }
                .buttonStyle(.ketchup)
                .disabled(busy)
                .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .background(Theme.cream)
        .navigationTitle("Delete account")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Delete account")
                    .font(.serif(.headline))
                    .foregroundStyle(Theme.ink)
            }
        }
        .alert("Delete your account?", isPresented: $confirm) {
            Button("Delete account", role: .destructive) { Task { await delete() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your messages and catch-ups are deleted for good.")
        }
        .navigationBarBackButtonHidden(busy)
        .interactiveDismissDisabled(busy)
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.inkSoft)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func delete() async {
        guard !deleting else { return }
        deleting = true
        error = nil
        do {
            try await app.deleteAccount()
            deleted()
        } catch {
            deleting = false
            self.error = error.localizedDescription
        }
    }
}
