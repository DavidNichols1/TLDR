//
//  ChatBubble.swift
//  Ketchup
//
//  Ported from AurariaGO's ChatComponents.ChatBubble, slimmed down: no
//  reactions or report menu. Other people's bubbles are card paper with a
//  hairline, mine are ink. A run of messages from one sender tucks its
//  inside corners in. When a Muse Spark ref chip jumps here, a mustard
//  marker sweeps behind the bubble.
//

import SwiftUI

struct ChatBubble: View {
    let text: String
    let mine: Bool
    var pending = false
    var failed = false
    /// Groups: the sender's name on the first bubble of a run.
    var senderName: String? = nil
    var senderColor: Color = Theme.inkSoft
    var time: Date? = nil
    /// Where this bubble sits in a run from one sender, for its corners.
    var startsRun = true
    var endsRun = true
    var highlighted = false
    let onRetry: () -> Void

    private static let round: CGFloat = 18
    private static let tucked: CGFloat = 6

    /// Round outside corners; the corners that face the rest of the run tuck in.
    private var shape: UnevenRoundedRectangle {
        let top = startsRun ? Self.round : Self.tucked
        let bottom = endsRun ? Self.round : Self.tucked
        return mine
            ? UnevenRoundedRectangle(topLeadingRadius: Self.round, bottomLeadingRadius: Self.round,
                                     bottomTrailingRadius: bottom, topTrailingRadius: top, style: .continuous)
            : UnevenRoundedRectangle(topLeadingRadius: top, bottomLeadingRadius: bottom,
                                     bottomTrailingRadius: Self.round, topTrailingRadius: Self.round, style: .continuous)
    }

    var body: some View {
        VStack(alignment: mine ? .trailing : .leading, spacing: 4) {
            if let senderName, !mine {
                Text(senderName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(senderColor)
                    .lineLimit(1)
                    .padding(.leading, 12)
            }
            Text(text)
                .font(.body)
                .foregroundStyle(mine ? Theme.onInk : Theme.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(mine ? Theme.ink : Theme.card, in: shape)
                .overlay {
                    if !mine { shape.strokeBorder(Theme.rule, lineWidth: 1) }
                }
                .background {
                    if highlighted { JumpMark() }
                }
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
                    Label("Not sent. Tap to retry", systemImage: "exclamationmark.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.ketchupText)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 6)
            }
        }
        .padding(mine ? .leading : .trailing, 56)
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
        .motion(value: highlighted)
    }
}

/// The jump-to-message highlight: one mustard marker pass behind the bubble,
/// reaching a little past it on every side. With Reduce Motion it's a plain
/// tint that fades in and out.
struct JumpMark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0

    /// How far the mark reaches past the bubble.
    private let reach = CGSize(width: 10, height: 8)

    var body: some View {
        GeometryReader { geo in
            if reduceMotion {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Theme.mustard.opacity(0.45))
                    .padding(-reach.height)
            } else {
                // MarkerStroke inks a band from 20% to 96% of its height, so
                // size its frame for that band to cover the bubble plus `reach`.
                let height = (geo.size.height + reach.height * 2) / 0.76
                MarkerStroke(progress: progress)
                    .fill(Theme.mustard.opacity(0.9))
                    .frame(width: geo.size.width + reach.width * 2, height: height)
                    .offset(x: -reach.width, y: -reach.height - height * 0.2)
            }
        }
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(Motion.sweep) { progress = 1 }
        }
    }
}
