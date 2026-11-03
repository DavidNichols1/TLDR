//
//  NameView.swift
//  Ketchup
//
//  Once, right after sign-up: the name your friends see (and the name Muse
//  Spark uses when it says "Sam owes you $12").
//

import SwiftUI

struct NameView: View {
    @Environment(AppModel.self) private var app
    @State private var name = ""
    @State private var busy = false
    @State private var error: String?
    @FocusState private var focused: Bool

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 54))
                .foregroundStyle(Theme.accent)
            Text("What should we call you?")
                .font(.title2.bold())
            Text("Your friends see this name in chats, and Muse Spark uses it in catch-ups.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TextField("Your name", text: $name)
                .textContentType(.givenName)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit { Task { await save() } }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            if let error {
                Text(error).font(.footnote).foregroundStyle(.red)
            }

            Button {
                Task { await save() }
            } label: {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(trimmed.isEmpty || trimmed.count > 30 || busy)

            Button("Keep “\(app.defaultName)”") { app.confirmName() }
                .font(.footnote)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 24)
        .onAppear {
            name = app.defaultName
            focused = true
        }
    }

    private func save() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try await app.rename(to: name)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
