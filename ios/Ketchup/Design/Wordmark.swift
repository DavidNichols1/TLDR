//
//  Wordmark.swift
//  Ketchup
//
//  "Ketchup" in New York black italic, with a squirt of mustard under it.
//

import SwiftUI

/// A wavy line, like a squirt of mustard: under the wordmark, or as a quiet
/// divider. An open path, so `.trim(from:to:)` draws it in. Stroke it with
/// round caps. The humps swell in the middle and trail off at the ends.
nonisolated struct Squiggle: Shape {
    var waves: Int = 6

    func path(in rect: CGRect) -> Path {
        let count = max(waves, 1)
        let width = rect.width / CGFloat(count)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        for i in 0..<count {
            let x = rect.minX + CGFloat(i) * width
            let swell = sin(.pi * (CGFloat(i) + 0.5) / CGFloat(count))
            let height = rect.height / 2 * (0.55 + 0.45 * swell)
            // Handles at 4/3 of the height put the hump's peak at `height`.
            let lift = (i.isMultiple(of: 2) ? -1 : 1) * height * 4 / 3
            path.addCurve(to: CGPoint(x: x + width, y: rect.midY),
                          control1: CGPoint(x: x + width / 3, y: rect.midY + lift),
                          control2: CGPoint(x: x + width * 2 / 3, y: rect.midY + lift))
        }
        return path
    }
}

/// The name, for the sign-in screen and anywhere the brand needs saying. A
/// fixed size on purpose: it's a logo, so it doesn't follow Dynamic Type.
/// `drawIn` draws the squiggle the first time it appears (it is simply there
/// with Reduce Motion on).
struct Wordmark: View {
    var size: CGFloat
    var drawIn: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn: CGFloat

    init(size: CGFloat = 44, drawIn: Bool = false) {
        self.size = size
        self.drawIn = drawIn
        _drawn = State(initialValue: drawIn ? 0 : 1)
    }

    var body: some View {
        Text(verbatim: "Ketchup")
            .font(.system(size: size, weight: .black, design: .serif).italic())
            .tracking(-size * 0.025)
            .foregroundStyle(Theme.ketchup)
            .padding(.bottom, size * 0.2)
            .overlay(alignment: .bottom) {
                Squiggle()
                    .trim(from: 0, to: drawn)
                    .stroke(Theme.mustard, style: StrokeStyle(lineWidth: max(2, size * 0.07),
                                                              lineCap: .round, lineJoin: .round))
                    .frame(height: size * 0.16)
                    .padding(.leading, size * 0.04)
                    .padding(.trailing, size * 0.1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "Ketchup"))
            .accessibilityAddTraits(.isHeader)
            .onAppear {
                guard drawn < 1 else { return }
                if reduceMotion {
                    drawn = 1
                } else {
                    withAnimation(Motion.squirt.delay(0.25)) { drawn = 1 }
                }
            }
    }
}
