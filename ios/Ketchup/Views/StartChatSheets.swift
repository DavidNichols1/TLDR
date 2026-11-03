//
//  StartChatSheets.swift
//  Ketchup
//
//  The inbox's "+" menu: name a new chat (and pick your people to add), or
//  join one with its 6-character invite code. Both only collect the input;
//  ChatsListView does the work.
//

import SwiftUI

/// Name a new chat, and pick any of your people to add straight in (People/).
/// `onCreate` runs with the name already in `name` and them in `picked`.
struct NewChatSheet: View {
    @Binding var name: String
    var people: [Person] = []
    var picked: Binding<Set<UUID>> = .constant([])
    let onCreate: () -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        StartChatPage(kicker: "New chat", title: "What's it called?", onCancel: cancel) {
            TextField("Chat name", text: $name, prompt: Text("Friday dinner").foregroundStyle(Theme.inkFaint))
                .textInputAutocapitalization(.sentences)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit { if !trimmed.isEmpty { onCreate() } }
                .paperField(focused: focused)

            if !people.isEmpty {
                SectionTitle("Add your people")
                    .padding(.top, 8)
                PeoplePicker(people: people, picked: picked)
            }

            Text(picked.wrappedValue.isEmpty
                 ? "You'll get an invite code to share."
                 : "They're in from the start. You'll also get an invite code to share.")
                .font(.footnote)
                .foregroundStyle(Theme.inkSoft)

            Button("Start the chat", action: onCreate)
                .buttonStyle(.ketchup)
                .disabled(trimmed.isEmpty)
                .padding(.top, 4)
        }
        .onAppear { focused = true }
    }

    private func cancel() {
        name = ""
        picked.wrappedValue = []
        dismiss()
    }
}

/// Join with an invite code: six boxes, like the sign-in code.
struct JoinChatSheet: View {
    @Binding var code: String
    let onJoin: () -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    static let length = 6

    var body: some View {
        StartChatPage(kicker: "Join a chat", title: "Got an invite code?", onCancel: cancel) {
            CodeField(text: $code, length: Self.length, kind: .inviteCode, focus: $focused,
                      label: "Invite code", onSubmit: { if code.count == Self.length { onJoin() } })
                .onChange(of: code) { _, new in
                    let cleaned = Self.clean(new)
                    if cleaned != new { code = cleaned }
                }

            Text("Ask someone in the chat for its invite code.")
                .font(.footnote)
                .foregroundStyle(Theme.inkSoft)

            Button("Join the chat", action: onJoin)
                .buttonStyle(.ketchup)
                .disabled(code.count != Self.length)
                .padding(.top, 4)
        }
        .onAppear { focused = true }
    }

    private func cancel() {
        code = ""
        dismiss()
    }

    /// Capital letters and numbers, at most six. From a pasted share message
    /// ("Join “Breck” on Ketchup with code WQGAEA") it keeps the word after
    /// "code", or else the last 6-character word.
    static func clean(_ raw: String) -> String {
        let upper = raw.uppercased()
        let kept = upper.filter { $0.isLetter || $0.isNumber }
        guard kept.count > length else { return kept }
        if let match = upper.firstMatch(of: /CODE[^A-Z0-9]+([A-Z0-9]{6})\b/) {
            return String(match.1)
        }
        if let word = upper.matches(of: /\b[A-Z0-9]{6}\b/).last {
            return String(word.output)
        }
        return String(kept.prefix(length))
    }
}

/// The page both sheets share: a cancel button, a kicker and a serif
/// question, then the form.
private struct StartChatPage<Form: View>: View {
    let kicker: String
    let title: String
    let onCancel: () -> Void
    @ViewBuilder let form: Form

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Kicker(kicker)
                        Text(title)
                            .font(.serif(.title))
                            .foregroundStyle(Theme.ink)
                            .accessibilityAddTraits(.isHeader)
                    }
                    .padding(.bottom, 6)
                    form
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Theme.cream)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.cream)
    }
}
