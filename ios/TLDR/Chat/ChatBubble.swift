//
//  ChatBubble.swift
//  TLDR
//
//  Ported from AurariaGO's ChatComponents.ChatBubble, slimmed down: no
//  reactions or report menu, and a highlight ring for when a Muse Spark
//  ref chip jumps here.
//

import SwiftUI

struct ChatBubble: View {
    let text: String
    let mine: Bool
    var pending = false
    var failed = false
    /// Groups: the sender's name on the first bubble of a run.
    var senderName: String? = nil
    var senderColor: Color = .secondary
    var time: Date? = nil
    var highlighted = false
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: mine ? .trailing : .leading, spacing: 3) {
            if let senderName, !mine {
                Text(senderName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(senderColor)
                    .lineLimit(1)
                    .padding(.leading, 6)
            }
            Text(text)
                .font(.body)
                .foregroundStyle(mine ? .white : Color.primary)
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .background(mine ? Theme.accent : Color(.secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    if highlighted {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Theme.aiDiagonal, lineWidth: 3)
                            .shadow(color: Theme.violet.opacity(0.6), radius: 8)
                    }
                }
                .scaleEffect(highlighted ? 1.04 : 1, anchor: mine ? .trailing : .leading)
                .opacity(pending ? 0.55 : 1)
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = text
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    if let time {
                        Text(time.formatted(date: .abbreviated, time: .shortened))
                    }
                }
                .onTapGesture { if failed { onRetry() } }
            if failed {
                Button(action: onRetry) {
                    Text("Not sent · tap to retry")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(mine ? .leading : .trailing, 56)
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
        .animation(.spring(duration: 0.35), value: highlighted)
    }
}
