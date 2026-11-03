//
//  ChatListRow.swift
//  Ketchup
//
//  One inbox row. A chat with a pile of unread messages gets a Muse Spark
//  nudge under the preview.
//

import SwiftUI

struct ChatListRow: View {
    let chat: ChatSummary

    private var preview: String {
        guard let text = chat.lastMessagePreview else { return "No messages yet" }
        if let who = chat.lastMessageSenderName { return "\(who): \(text)" }
        return text
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(Theme.initials(chat.name))
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(Theme.personColor(chat.id).gradient, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(chat.name)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    Text((chat.lastMessageAt ?? chat.createdAt).inboxStamp)
                        .font(.caption)
                        .foregroundStyle(chat.unreadCount > 0 ? Theme.accent : .secondary)
                }
                HStack(alignment: .top) {
                    Text(preview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer()
                    if chat.unreadCount > 0 {
                        Text(chat.unreadCount > 999 ? "999+" : "\(chat.unreadCount)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .frame(minWidth: 22, minHeight: 22)
                            .background(Theme.accent, in: Capsule())
                    }
                }
                if chat.unreadCount >= 10 {
                    Label("Catch up in seconds", systemImage: Theme.aiSymbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.aiGradient)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
