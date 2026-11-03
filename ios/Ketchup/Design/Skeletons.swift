//
//  Skeletons.swift
//  Ketchup
//
//  Blank paper in the shape of what's coming, for a screen's first load:
//  the inbox's rows, a thread's bubbles, the skim window's lines. The
//  layout is there from the first frame and the real rows land in its
//  place. Bars are the hairline color; bubbles are card paper with a
//  hairline, like the real ones. The paper breathes slowly (an opacity
//  pulse: a shimmer band would be a gradient) and holds still with Reduce
//  Motion.
//
//  Rarely seen: after the first launch the copy the phone kept
//  (Store/DeviceStore.swift) shows instead. Shapes adapted from AurariaGO's
//  Skeletons.swift.
//

import SwiftUI

// MARK: - Pieces

/// Makes a skeleton breathe, and gives VoiceOver one "Loading" for all of it.
struct Skeleton<Content: View>: View {
    let label: String
    let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ label: String = "Loading", @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        content
            .phaseAnimator(reduceMotion ? [1.0] : [1.0, 0.45]) { view, opacity in
                view.opacity(opacity)
            } animation: { _ in
                .easeInOut(duration: 0.9)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
    }
}

/// One blank line of type: a rounded bar of hairline paper, sitting in a
/// line of `line` points (so rows keep their real height at every text
/// size). A fixed `width`, or a `share` of the width it's offered.
struct Bone: View {
    var width: CGFloat? = nil
    var share: CGFloat = 1
    var height: CGFloat = 9
    var line: CGFloat = 20
    var color: Color = Theme.rule

    var body: some View {
        Group {
            if let width {
                Capsule().fill(color).frame(width: width, height: height)
            } else {
                GeometryReader { geo in
                    Capsule().fill(color).frame(width: geo.size.width * share, height: height)
                }
                .frame(height: height)
            }
        }
        .frame(height: line, alignment: .center)
    }
}

// MARK: - Inbox

/// The inbox before my_chats answers: rows in ChatListRow's shape (a tile,
/// a name and a time, a preview line or two), with its hairlines.
struct InboxSkeleton: View {
    var rows = 6

    @ScaledMetric(relativeTo: .headline) private var monogramSize: CGFloat = 48
    @ScaledMetric(relativeTo: .headline) private var nameLine: CGFloat = 22
    @ScaledMetric(relativeTo: .subheadline) private var previewLine: CGFloat = 20

    /// Name widths and preview shares, so the rows don't look stamped out.
    private static let shapes: [(name: CGFloat, preview: CGFloat, twoLines: Bool)] = [
        (132, 0.92, true), (96, 0.66, false), (150, 0.84, false),
        (108, 0.9, true), (124, 0.58, false), (88, 0.76, false),
    ]

    var body: some View {
        Skeleton("Loading your chats") {
            VStack(spacing: 0) {
                ForEach(0..<rows, id: \.self) { i in
                    let shape = Self.shapes[i % Self.shapes.count]
                    HStack(alignment: .top, spacing: 14) {
                        RoundedRectangle(cornerRadius: monogramSize * 0.3, style: .continuous)
                            .fill(Theme.rule)
                            .frame(width: monogramSize, height: monogramSize)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Bone(width: shape.name, height: 12, line: nameLine)
                                Spacer(minLength: 0)
                                Bone(width: 36, height: 8, line: nameLine)
                            }
                            Bone(share: shape.preview, line: previewLine)
                            if shape.twoLines {
                                Bone(share: shape.preview * 0.55, line: previewLine)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    if i < rows - 1 {
                        Rectangle()
                            .fill(Theme.rule)
                            .frame(height: 1)
                            .padding(.leading, 20 + monogramSize + 14)
                    }
                }
            }
        }
    }
}

// MARK: - Thread

/// A thread before its first page: a day line, then bubbles from a few
/// people in ChatBubble's paper (theirs card with a hairline, mine plain
/// hairline paper), sitting at the bottom where a thread opens.
struct ThreadSkeleton: View {
    @ScaledMetric(relativeTo: .body) private var textLine: CGFloat = 22
    @ScaledMetric(relativeTo: .caption) private var nameLine: CGFloat = 16

    private enum Piece {
        case day
        /// Their bubble: a name over the first of a run, the widths of its lines.
        case theirs(name: Bool, lines: [CGFloat], startsRun: Bool, endsRun: Bool)
        case mine(width: CGFloat, lines: Int)
    }

    private static let pieces: [Piece] = [
        .day,
        .theirs(name: true, lines: [168], startsRun: true, endsRun: false),
        .theirs(name: false, lines: [214, 120], startsRun: false, endsRun: true),
        .mine(width: 132, lines: 1),
        .theirs(name: true, lines: [146], startsRun: true, endsRun: true),
        .theirs(name: true, lines: [196, 172], startsRun: true, endsRun: false),
        .theirs(name: false, lines: [92], startsRun: false, endsRun: true),
        .mine(width: 186, lines: 2),
        .theirs(name: true, lines: [120], startsRun: true, endsRun: true),
    ]

    var body: some View {
        Skeleton("Loading messages") {
            VStack(spacing: 0) {
                ForEach(Self.pieces.indices, id: \.self) { i in
                    piece(Self.pieces[i])
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .clipped()
        }
    }

    @ViewBuilder
    private func piece(_ piece: Piece) -> some View {
        switch piece {
        case .day:
            Bone(width: 64, height: 7, line: 12)
                .frame(maxWidth: .infinity)
                .padding(.top, 18)
                .padding(.bottom, 6)
        case .theirs(let name, let lines, let startsRun, let endsRun):
            let shape = UnevenRoundedRectangle(topLeadingRadius: startsRun ? 18 : 6,
                                               bottomLeadingRadius: endsRun ? 18 : 6,
                                               bottomTrailingRadius: 18, topTrailingRadius: 18,
                                               style: .continuous)
            VStack(alignment: .leading, spacing: 4) {
                if name {
                    Bone(width: 52, height: 7, line: nameLine)
                        .padding(.leading, 12)
                }
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(lines.indices, id: \.self) { j in
                        Bone(width: lines[j], height: 8, line: textLine)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Theme.card, in: shape)
                .overlay { shape.strokeBorder(Theme.rule, lineWidth: 1) }
            }
            .padding(.trailing, 56)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, startsRun ? 10 : 0)
            .padding(.vertical, 1.5)
        case .mine(let width, let lines):
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.rule)
                .frame(width: width + 28, height: textLine * CGFloat(lines) + 18)
                .padding(.leading, 56)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 10)
                .padding(.vertical, 1.5)
        }
    }
}

// MARK: - Skim window

/// The skim window's rows before the chat's messages are here: a name and
/// a line of text each, in the window's own row height.
struct SkimSkeletonRows: View {
    let rows: Int
    let rowHeight: CGFloat
    let nameWidth: CGFloat

    private static let shares: [CGFloat] = [0.9, 0.62, 0.82, 0.5, 0.74]

    var body: some View {
        Skeleton {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<rows, id: \.self) { i in
                    HStack(spacing: 10) {
                        Bone(width: nameWidth * 0.7, height: 8, line: rowHeight)
                            .frame(width: nameWidth, alignment: .leading)
                        Bone(share: Self.shares[i % Self.shares.count], height: 8, line: rowHeight)
                    }
                }
            }
        }
    }
}
