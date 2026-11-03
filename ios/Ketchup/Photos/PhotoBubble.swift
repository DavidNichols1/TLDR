//
//  PhotoBubble.swift
//  Ketchup
//
//  A photo in the thread: the photo at its own shape (kept between 1:2 and
//  2.2:1, so a panorama or a long screenshot doesn't take over the thread),
//  its caption under it in the same bubble, and the same paper, ink and run
//  corners as a text bubble. It's laid out from the stored size before it
//  loads, so nothing jumps. A tap opens the viewer; while it uploads, a ring
//  fills over it.
//

import SwiftUI

struct PhotoBubble: View {
    let message: Message
    let mine: Bool
    var senderName: String? = nil
    var senderColor: Color = Theme.inkSoft
    var startsRun = true
    var endsRun = true
    var highlighted = false
    /// Someone else's photo: their name opens their profile, and the long
    /// press offers Report (People/).
    var onSenderTap: (() -> Void)? = nil
    var onReport: (() -> Void)? = nil
    let onOpen: () -> Void
    let onRetry: () -> Void

    @Environment(\.displayScale) private var displayScale
    @ScaledMetric(relativeTo: .body) private var maxWidth: CGFloat = 240

    private static let round: CGFloat = 18
    private static let tucked: CGFloat = 6

    /// Same corners as ChatBubble: round outside, tucked toward the run.
    private var shape: UnevenRoundedRectangle {
        let top = startsRun ? Self.round : Self.tucked
        let bottom = endsRun ? Self.round : Self.tucked
        return mine
            ? UnevenRoundedRectangle(topLeadingRadius: Self.round, bottomLeadingRadius: Self.round,
                                     bottomTrailingRadius: bottom, topTrailingRadius: top, style: .continuous)
            : UnevenRoundedRectangle(topLeadingRadius: top, bottomLeadingRadius: bottom,
                                     bottomTrailingRadius: Self.round, topTrailingRadius: Self.round, style: .continuous)
    }

    /// The photo's box: its own shape within limits, never wider than
    /// `maxWidth` or taller than 1.25 of it.
    static func box(width: Int?, height: Int?, maxWidth: CGFloat) -> CGSize {
        guard let width, let height, width > 0, height > 0 else {
            return CGSize(width: maxWidth, height: maxWidth * 0.75)
        }
        let ratio = min(max(CGFloat(width) / CGFloat(height), 0.5), 2.2)
        let maxHeight = maxWidth * 1.25
        var size = CGSize(width: maxWidth, height: maxWidth / ratio)
        if size.height > maxHeight { size = CGSize(width: maxHeight * ratio, height: maxHeight) }
        return size
    }

    var body: some View {
        let box = Self.box(width: message.imageWidth, height: message.imageHeight, maxWidth: maxWidth)
        VStack(alignment: mine ? .trailing : .leading, spacing: 4) {
            if let senderName, !mine {
                SenderName(name: senderName, color: senderColor, onTap: onSenderTap)
            }
            VStack(alignment: .leading, spacing: 0) {
                photo(box)
                if !message.body.isEmpty {
                    Text(message.body)
                        .font(.body)
                        .foregroundStyle(mine ? Theme.onInk : Theme.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(width: box.width)
            .background(mine ? Theme.ink : Theme.card)
            .clipShape(shape)
            .overlay { shape.strokeBorder(mine ? Theme.ink : Theme.rule, lineWidth: 1) }
            .contentShape(shape)
            .background {
                if highlighted { JumpMark() }
            }
            .onTapGesture { message.failed ? onRetry() : onOpen() }
            .contextMenu {
                if !message.body.isEmpty {
                    Button {
                        UIPasteboard.general.string = message.body
                    } label: {
                        Label("Copy caption", systemImage: "doc.on.doc")
                    }
                }
                if let onReport {
                    Button(role: .destructive, action: onReport) {
                        Label("Report", systemImage: "flag")
                    }
                }
                Text(message.createdAt.formatted(date: .abbreviated, time: .shortened))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(message.failed ? "Tries sending it again" : "Opens the photo")
            if message.failed {
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
        .motion(value: message.pending)
    }

    private func photo(_ box: CGSize) -> some View {
        RemoteImage(object: message.smallPhoto,
                    pixels: RemoteImages.pixels(points: max(box.width, box.height), scale: displayScale)) { image in
            image
                .resizable()
                .scaledToFill()
        } placeholder: { failed in
            ZStack {
                Theme.rule.opacity(0.6)
                if failed {
                    Image(systemName: "photo")
                        .font(.title3)
                        .foregroundStyle(Theme.inkFaint)
                }
            }
        }
        .frame(width: box.width, height: box.height)
        .clipped()
        .overlay {
            if message.pending { UploadRing(progress: PhotoUploads.shared.progress[message.id]) }
        }
    }

    private var accessibilityText: String {
        var parts = [mine ? "Your photo" : "Photo from \(senderName ?? "someone")"]
        if !message.body.isEmpty { parts.append(message.body) }
        if message.pending { parts.append("Sending") }
        if message.failed { parts.append("Not sent") }
        return parts.joined(separator: ", ")
    }
}

/// Upload progress over a photo: an ink ring filling its hairline track on
/// a cream disc, a sliver of it until the first bytes are counted.
private struct UploadRing: View {
    let progress: Double?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 40

    var body: some View {
        ZStack {
            Circle().fill(Theme.cream.opacity(0.92))
            Circle()
                .stroke(Theme.rule, lineWidth: 3)
                .padding(8)
            Circle()
                .trim(from: 0, to: max(0.04, progress ?? 0.04))
                .stroke(Theme.ink, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(8)
                .animation(Motion.choose(Motion.snappy, reduceMotion: reduceMotion), value: progress)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
