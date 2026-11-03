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
    @ScaledMetric(relativeTo: .body) private var monogramSize: CGFloat = 30

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Kicker("Last step")
                Text("What do your friends call you?")
                    .font(.serif(.largeTitle))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 8)
                Text("They see it in your chats, and \(Theme.modelName) uses it in catch-ups.")
                    .font(.body)
                    .foregroundStyle(Theme.inkSoft)
                    .padding(.top, 10)

                // The monogram follows what you type: how you'll look in member lists.
                HStack(spacing: 12) {
                    Monogram(name: trimmed.isEmpty ? "?" : trimmed, size: monogramSize)
                    TextField("Your name", text: $name, prompt: Text("Your name").foregroundStyle(Theme.inkFaint))
                        .textContentType(.givenName)
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit { Task { await save() } }
                }
                .paperField(focused: focused)
                .padding(.top, 28)

                if let error {
                    FormError(text: error)
                        .padding(.top, 12)
                }

                Button {
                    Task { await save() }
                } label: {
                    ZStack {
                        Text("Save my name").opacity(busy ? 0 : 1)
                        if busy { ProgressView().tint(Theme.onKetchup) }
                    }
                }
                .buttonStyle(.ketchup)
                .disabled(trimmed.isEmpty || trimmed.count > 30 || busy)
                .padding(.top, 12)

                Button("Keep “\(app.defaultName)”") { app.confirmName() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 18)
            }
            .padding(.horizontal, 24)
            .padding(.top, 48)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.cream)
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
