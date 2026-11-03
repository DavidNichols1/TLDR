//
//  ChatInputBar.swift
//  Ketchup
//
//  Ported from AurariaGO's ChatComponents.ChatInputBar; the cap matches
//  messages_body_check (2,000 characters). A paper field and a ketchup
//  send button that only turns red when there's something to send.
//

import SwiftUI

struct ChatInputBar: View {
    let placeholder: String
    @Binding var text: String
    var disabled = false
    let onSend: () -> Void

    @FocusState private var focused: Bool
    @ScaledMetric(relativeTo: .body) private var sendSize: CGFloat = 40

    private var canSend: Bool { Self.sendable(text) != nil && !disabled }

    var body: some View {
        let field = RoundedRectangle(cornerRadius: 20, style: .continuous)
        HStack(alignment: .bottom, spacing: 10) {
            TextField(placeholder, text: $text, prompt: Text(placeholder).foregroundStyle(Theme.inkFaint), axis: .vertical)
                .lineLimit(1...5)
                .font(.body)
                .foregroundStyle(Theme.ink)
                .tint(Theme.ketchupText)
                .focused($focused)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .frame(minHeight: sendSize)
                .background(Theme.card, in: field)
                .overlay {
                    field.strokeBorder(focused ? Theme.inkSoft : Theme.rule, lineWidth: 1)
                }
                .disabled(disabled)

            Button(action: onSend) {
                Image(systemName: "arrow.up")
                    .font(.body.weight(.bold))
                    .foregroundStyle(canSend ? Theme.onKetchup : Theme.inkFaint)
                    .frame(width: sendSize, height: sendSize)
                    .background(canSend ? Theme.ketchup : Theme.rule, in: Circle())
            }
            .buttonStyle(.pressable)
            .disabled(!canSend)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.cream)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.rule).frame(height: 1)
        }
        .motion(value: canSend)
        .motion(value: focused)
    }

    /// The trimmed text, or nil when it's empty or over the cap.
    static func sendable(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return (t.isEmpty || t.count > 2000) ? nil : t
    }
}
