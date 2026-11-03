//
//  ChatListRow.swift
//  Ketchup
//
//  One inbox row. A chat with a pile of unread messages gets a catch-up
//  nudge under the preview, with the ketchup drop.
//

import SwiftUI

struct ChatListRow: View {
    let chat: ChatSummary

    @ScaledMetric(relativeTo: .headline) private var monogramSize: CGFloat = 48
    @ScaledMetric(relativeTo: .caption) private var dropSize: CGFloat = 12

    /// Unread count that earns the nudge (ChatModel prefetches a catch-up from here too).
    static let nudgeAt = 15

    private var unread: Int { chat.unreadCount }
    private var count: String { unread > 999 ? "999+" : "\(unread)" }

    private var preview: Text {
        guard let text = chat.lastMessagePreview else { return Text("No messages yet") }
        if let who = chat.lastMessageSenderName {
            return Text("\(Text("\(who):").fontWeight(.medium).foregroundStyle(Theme.ink)) \(text)")
        }
        return Text(text)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Monogram(name: chat.name, size: monogramSize)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(chat.name)
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text((chat.lastMessageAt ?? chat.createdAt).inboxStamp)
                        .font(.mono(.caption))
                        .foregroundStyle(unread > 0 ? Theme.ink : Theme.inkSoft)
                }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    preview
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSoft)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    if unread > 0 {
                        Text(count)
                            .font(.mono(.caption, weight: .bold))
                            .foregroundStyle(Theme.onMustard)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .frame(minWidth: 24)
                            .background(Theme.mustard, in: Capsule())
                    }
                }
                if unread >= Self.nudgeAt {
                    HStack(spacing: 6) {
                        KetchupDrop()
                            .fill(Theme.ketchupText)
                            .frame(width: dropSize, height: dropSize)
                        Text("\(count) new · catch up")
                            .font(.mono(.caption, weight: .semibold))
                    }
                    .foregroundStyle(Theme.ketchupText)
                    .padding(.top, 3)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts = [chat.name]
        if unread > 0 { parts.append(unread == 1 ? "1 unread message" : "\(unread) unread messages") }
        if let text = chat.lastMessagePreview {
            parts.append([chat.lastMessageSenderName, text].compactMap { $0 }.joined(separator: ": "))
        }
        parts.append((chat.lastMessageAt ?? chat.createdAt).inboxStamp)
        return parts.joined(separator: ", ")
    }
}
