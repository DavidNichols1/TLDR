//
//  ChatInputBar.swift
//  TLDR
//
//  Ported from AurariaGO's ChatComponents.ChatInputBar; the cap matches
//  messages_body_check (2,000 characters).
//

import SwiftUI

struct ChatInputBar: View {
    let placeholder: String
    @Binding var text: String
    var disabled = false
    let onSend: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField(placeholder, text: $text, axis: .vertical)
                .lineLimit(1...5)
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .disabled(disabled)

            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(Self.sendable(text) == nil || disabled ? Color.secondary.opacity(0.4) : Theme.accent)
            }
            .buttonStyle(.plain)
            .disabled(Self.sendable(text) == nil || disabled)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    /// The trimmed text, or nil when it's empty or over the cap.
    static func sendable(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return (t.isEmpty || t.count > 2000) ? nil : t
    }
}
