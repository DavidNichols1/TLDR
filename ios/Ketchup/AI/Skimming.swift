//
//  Skimming.swift
//  Ketchup
//
//  What a Muse Spark sheet shows while it waits: the chat's real messages
//  run past a small window and a marker passes over each line in turn, with
//  an honest clock and how long it usually takes. Only the few lines in the
//  window are built at any moment, so a chat of any size runs the same.
//

import SwiftUI

/// One line in the window: who sent it, in their chat color, and what it says.
struct SkimLine {
    let name: String
    let text: String
    let color: Color
}

struct SkimmingView: View {
    /// "Reading 302 messages".
    let title: String
    /// Under the title, in small type.
    var subtitle: String? = nil
    /// "Usually about 20 seconds".
    let usually: String
    /// The messages to run past, oldest first. They loop if the wait runs long.
    let lines: [SkimLine]
    /// Rows in the window. The marker reads the middle one.
    var rows = 5
    /// Big when the wait is the whole page, smaller under a question.
    var titleFont: Font = .serif(.title)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .subheadline) private var rowHeight: CGFloat = 30
    @ScaledMetric(relativeTo: .subheadline) private var nameWidth: CGFloat = 58
    @State private var start = Date.now

    /// Seconds per line, and the part of that spent moving up a row.
    private static let beat: Double = 0.62
    private static let lift: Double = 0.2
    /// Past this, the hint stops promising and owns up.
    private static let patience = 35

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(titleFont)
                    .foregroundStyle(Theme.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSoft)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            if !lines.isEmpty {
                window
            }
            clock
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: The window

    private var window: some View {
        Group {
            if reduceMotion {
                still
            } else {
                TimelineView(.animation) { context in
                    moving(at: context.date.timeIntervalSince(start))
                }
            }
        }
        .frame(height: rowHeight * CGFloat(rows), alignment: .top)
        .clipped()
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .paperCard(padding: 0)
        .accessibilityHidden(true)
    }

    /// Where everything is `t` seconds in. The line being read sits in the
    /// middle row while the marker sweeps across it, then the list moves up
    /// a row and the next line gets read. Lines already read keep a fading
    /// trace of the marker.
    private func moving(at t: TimeInterval) -> some View {
        let step = Int(t / Self.beat)
        let phase = t - Double(step) * Self.beat
        let reading = Self.beat - Self.lift
        let sweep = Self.easeOut(min(phase / reading, 1))
        let rise = Self.easeInOut(max(0, (phase - reading) / Self.lift))
        let slot = rows / 2
        return ZStack(alignment: .topLeading) {
            // Line `step` is being read; one more row either side slides in and out.
            ForEach((step - slot - 1)...(step + rows - slot), id: \.self) { index in
                if index >= 0 {
                    // In rows from the top of the window, and from the reading row.
                    let position = Double(index - step + slot) - rise
                    let distance = position - Double(slot)
                    row(lines[index % lines.count],
                        marker: index < step ? 1 : (index == step ? sweep : 0),
                        markerFade: max(0, 1 + distance * 0.8),
                        fade: max(0.22, 1 - abs(distance) * 0.32))
                        .frame(height: rowHeight)
                        .offset(y: position * rowHeight)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Reduce Motion: the first few lines standing still, the first one marked.
    private var still: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.prefix(rows).enumerated()), id: \.offset) { i, line in
                row(line, marker: i == 0 ? 1 : 0, markerFade: 1, fade: i == 0 ? 1 : 0.6)
                    .frame(height: rowHeight)
            }
        }
    }

    private func row(_ line: SkimLine, marker: Double, markerFade: Double, fade: Double) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(verbatim: line.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(line.color)
                .frame(width: nameWidth, alignment: .leading)
            Text(verbatim: line.text)
                .font(.subheadline)
                .foregroundStyle(Theme.ink)
                .background {
                    if marker > 0 {
                        MarkerStroke(progress: marker)
                            .fill(Theme.mustard.opacity((colorScheme == .dark ? 0.45 : 0.85) * markerFade))
                            .padding(.horizontal, -4)
                    }
                }
        }
        .lineLimit(1)
        .opacity(fade)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: The clock

    private var clock: some View {
        TimelineView(.periodic(from: start, by: 1)) { context in
            let seconds = max(0, Int(context.date.timeIntervalSince(start)))
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond)))
                    .font(.mono(.body, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(seconds < Self.patience ? usually : "Taking longer than usual")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSoft)
            }
            .accessibilityAddTraits(.updatesFrequently)
        }
    }

    // MARK: Curves

    private static func easeOut(_ x: Double) -> Double { 1 - pow(1 - x, 3) }

    private static func easeInOut(_ x: Double) -> Double {
        x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
    }
}

extension SkimLine {
    /// Up to `limit` of a chat's messages as window lines, from `start` on.
    static func lines(from model: ChatModel, startingAt start: UUID?, limit: Int = 200) -> [SkimLine] {
        let messages = model.messages
        let first = start.flatMap { id in messages.firstIndex { $0.id == id } }
            ?? max(0, messages.count - limit)
        return messages[first...].prefix(limit).map { message in
            let name = model.name(of: message.sender)
            return SkimLine(name: name,
                            text: message.body.replacingOccurrences(of: "\n", with: " "),
                            color: RefChip.color(for: name))
        }
    }
}
