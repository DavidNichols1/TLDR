//
//  RefChip.swift
//  TLDR
//
//  Every Muse Spark item cites the messages behind it. A chip shows who
//  said it and how it starts; tapping it closes the sheet and jumps the
//  chat to that exact message.
//

import SwiftUI

/// How an AI sheet talks to the chat underneath it.
struct RefContext {
    /// Sender name and text of a loaded message, or nil if it isn't loaded.
    let preview: (UUID) -> (name: String, text: String)?
    /// Close the sheet and scroll the chat to this message.
    let jump: (UUID) -> Void
}

struct RefChip: View {
    let id: UUID
    let context: RefContext

    var body: some View {
        Button {
            context.jump(id)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.caption2.weight(.bold))
                if let p = context.preview(id) {
                    Text(p.name).fontWeight(.semibold)
                    Text(p.text).foregroundStyle(.secondary)
                } else {
                    Text("View message")
                }
            }
            .font(.caption)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .frame(maxWidth: 230, alignment: .leading)
            .background(Theme.violet.opacity(0.10), in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.violet.opacity(0.30), lineWidth: 0.8))
            .foregroundStyle(Theme.indigo)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show the message in the chat")
    }
}

/// A row of ref chips that wraps.
struct RefChips: View {
    let refs: [UUID]
    let context: RefContext

    var body: some View {
        if !refs.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(refs, id: \.self) { RefChip(id: $0, context: context) }
            }
        }
    }
}
