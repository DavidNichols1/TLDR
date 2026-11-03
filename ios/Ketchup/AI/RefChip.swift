//
//  RefChip.swift
//  Ketchup
//
//  Every Muse Spark item cites the messages behind it. A chip shows who
//  said it, in their chat color, and how it starts; tapping it closes the
//  sheet and jumps the chat to that exact message.
//

import SwiftUI

/// How an AI sheet talks to the chat underneath it.
struct RefContext {
    /// Sender name and text of a loaded message, or nil if it isn't loaded.
    let preview: (UUID) -> (name: String, text: String)?
    /// Close the sheet and scroll the chat to this message.
    let jump: (UUID) -> Void
    /// What a tap does, for VoiceOver. A source with no chat in Ketchup to
    /// jump to (a thread read off Instagram) shows the whole message instead.
    var hint = "Shows it in the chat"
    /// A source that's a photo: its small copy, shown in the chip.
    var photo: (UUID) -> StorageObject? = { _ in nil }
}

/// One source: "● Maya · so the Airbnb is now…". A photo shows itself,
/// small, where the dot would be.
struct RefChip: View {
    let id: UUID
    let context: RefContext

    @Environment(\.displayScale) private var displayScale
    @ScaledMetric(relativeTo: .caption) private var thumbnail: CGFloat = 16

    var body: some View {
        let preview = context.preview(id)
        let dot = Circle()
            .fill(preview.map { Self.color(for: $0.name) } ?? Theme.inkFaint)
            .frame(width: 7, height: 7)
        Button {
            context.jump(id)
        } label: {
            HStack(spacing: 6) {
                if let photo = context.photo(id) {
                    RemoteImage(object: photo, pixels: RemoteImages.pixels(points: thumbnail, scale: displayScale)) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: { _ in
                        Theme.rule
                    }
                    .frame(width: thumbnail, height: thumbnail)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .padding(.leading, -3)
                } else {
                    dot
                }
                if let preview {
                    Text("\(Text(verbatim: preview.name).fontWeight(.semibold).foregroundStyle(Theme.ink)) · \(Text(verbatim: preview.text))")
                } else {
                    Text("See the message")
                }
            }
            .font(.caption)
            .foregroundStyle(Theme.inkSoft)
            .lineLimit(1)
            .padding(.leading, 9)
            .padding(.trailing, 11)
            .padding(.vertical, 6)
            .background(Theme.cream, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.rule, lineWidth: 1))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(preview.map { "\($0.name): \($0.text)" } ?? "A message")
        .accessibilityHint(context.hint)
    }

    /// A person's chat color. "You" is the reader, who writes in ink.
    static func color(for name: String) -> Color {
        name == "You" ? Theme.ink : Theme.personColor(name: name)
    }
}

/// An item's sources. Past `limit` they fold into a "+2" that opens the
/// rest in place. One chip and its "+2" share a line, the chip giving way;
/// more than one wrap.
struct RefChips: View {
    let refs: [UUID]
    let context: RefContext
    var limit = 1

    @State private var showAll = false

    var body: some View {
        if !refs.isEmpty {
            let shown = showAll ? refs : Array(refs.prefix(max(limit, 1)))
            Group {
                if shown.count == 1 {
                    HStack(spacing: 6) {
                        chips(shown)
                    }
                } else {
                    FlowLayout(spacing: 6) {
                        chips(shown)
                    }
                }
            }
            .motion(value: showAll)
        }
    }

    @ViewBuilder
    private func chips(_ shown: [UUID]) -> some View {
        ForEach(Array(shown.enumerated()), id: \.offset) { _, id in
            RefChip(id: id, context: context)
        }
        let hidden = refs.count - shown.count
        if hidden > 0 {
            Button {
                showAll = true
            } label: {
                Text(verbatim: "+\(hidden)")
                    .font(.mono(.caption, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .overlay(Capsule().strokeBorder(Theme.rule, lineWidth: 1))
            }
            .buttonStyle(.pressable)
            .fixedSize()
            .accessibilityLabel(hidden == 1 ? "1 more source" : "\(hidden) more sources")
        }
    }
}
