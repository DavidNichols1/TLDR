//
//  Marker.swift
//  Ketchup
//
//  The mustard highlighter: how Ketchup says "this part matters" (a time,
//  an amount, your name) instead of bold color or a badge.
//

import SwiftUI

/// One highlighter pass, for filling behind text. `progress` draws it from
/// the left (0 is nothing, 1 is the whole pass) and animates. The ends lean
/// like a chisel tip and the edges wobble a little, so it looks hand done.
nonisolated struct MarkerStroke: Shape {
    var progress: CGFloat = 1

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let reach = rect.width * min(max(progress, 0), 1)
        guard reach > 0.5, rect.height > 1 else { return Path() }
        let height = rect.height
        let lean = min(height * 0.3, 7, reach * 0.4)
        let wobble = min(height * 0.045, 1.4)
        let top = rect.minY + height * 0.2
        let bottom = rect.maxY - height * 0.04

        // A slow wave along each edge, and a 1 pt climb across the full width.
        func edge(_ y: CGFloat, _ x: CGFloat, phase: CGFloat) -> CGPoint {
            let t = (x - rect.minX) / max(rect.width, 1)
            return CGPoint(x: x, y: y + wobble * sin(t * 2 * .pi * 1.1 + phase) - t)
        }
        let step: CGFloat = 4
        var path = Path()

        // Top edge, left to right, starting `lean` in from the left end.
        var x = rect.minX + lean
        path.move(to: edge(top, x, phase: 0))
        let end = rect.minX + reach
        while x < end {
            x = min(x + step, end)
            path.addLine(to: edge(top, x, phase: 0))
        }
        // The leading end slants back to the bottom edge, then right to left.
        x = end - lean
        path.addLine(to: edge(bottom, x, phase: 2.1))
        while x > rect.minX {
            x = max(x - step, rect.minX)
            path.addLine(to: edge(bottom, x, phase: 2.1))
        }
        path.closeSubpath()
        return path
    }
}

extension View {
    /// Draws the mustard marker behind this view: a word, a time, an amount.
    /// Keep it to a phrase on one line. With `sweep` it draws on left to right
    /// when it appears or turns on (`delay` staggers several); with Reduce
    /// Motion on it simply appears. In dark mode it drops to 45% so light ink
    /// stays readable on it.
    func marked(_ isOn: Bool = true, color: Color = Theme.mustard, sweep: Bool = false, delay: Double = 0) -> some View {
        modifier(MarkerModifier(isOn: isOn, color: color, sweep: sweep, delay: delay))
    }
}

private struct MarkerModifier: ViewModifier {
    let isOn: Bool
    let color: Color
    let sweep: Bool
    let delay: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var progress: CGFloat

    init(isOn: Bool, color: Color, sweep: Bool, delay: Double) {
        self.isOn = isOn
        self.color = color
        self.sweep = sweep
        self.delay = delay
        _progress = State(initialValue: isOn && !sweep ? 1 : 0)
    }

    func body(content: Content) -> some View {
        content
            .background {
                MarkerStroke(progress: progress)
                    .fill(color.opacity(colorScheme == .dark ? 0.45 : 0.85))
                    .padding(.horizontal, -4)
                    .accessibilityHidden(true)
            }
            .onAppear { show(isOn) }
            .onChange(of: isOn) { _, on in show(on) }
    }

    private func show(_ on: Bool) {
        let target: CGFloat = on ? 1 : 0
        guard progress != target else { return }
        if reduceMotion || (on && !sweep) {
            progress = target
        } else if on {
            withAnimation(Motion.sweep.delay(delay)) { progress = 1 }
        } else {
            withAnimation(Motion.snappy) { progress = 0 }
        }
    }
}

// MARK: - Inside a sentence

extension Text {
    /// Tags part of a sentence for the marker, so it follows the words as they
    /// wrap: `Text("You owe Maya \(Text("$90").markedRun()) for the Airbnb.")`.
    /// Nothing shows until the sentence gets `markRuns()`.
    func markedRun() -> Text {
        customAttribute(MarkedRun())
    }
}

extension View {
    /// Draws the marker behind every `markedRun()` in this text, line by line.
    /// With `sweep` they draw on when the text appears (`delay` staggers);
    /// with Reduce Motion on they simply appear.
    func markRuns(color: Color = Theme.mustard, sweep: Bool = false, delay: Double = 0) -> some View {
        modifier(MarkRunsModifier(color: color, sweep: sweep, delay: delay))
    }
}

nonisolated private struct MarkedRun: TextAttribute {}

private struct MarkRunsModifier: ViewModifier {
    let color: Color
    let sweep: Bool
    let delay: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var progress: CGFloat

    init(color: Color, sweep: Bool, delay: Double) {
        self.color = color
        self.sweep = sweep
        self.delay = delay
        _progress = State(initialValue: sweep ? 0 : 1)
    }

    func body(content: Content) -> some View {
        content
            .textRenderer(MarkerRenderer(progress: progress,
                                         fill: color.opacity(colorScheme == .dark ? 0.45 : 0.85)))
            .onAppear {
                guard progress < 1 else { return }
                if reduceMotion {
                    progress = 1
                } else {
                    withAnimation(Motion.sweep.delay(delay)) { progress = 1 }
                }
            }
    }
}

/// Paints a marker stroke behind each tagged run, then the line over it.
nonisolated private struct MarkerRenderer: TextRenderer {
    var progress: CGFloat
    var fill: Color

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var displayPadding: EdgeInsets { EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4) }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            for run in line where run[MarkedRun.self] != nil {
                let bounds = run.typographicBounds.rect.insetBy(dx: -3, dy: 0)
                context.fill(MarkerStroke(progress: progress).path(in: bounds), with: .color(fill))
            }
            context.draw(line)
        }
    }
}
