//
//  UsageBar.swift
//  Ketchup
//
//  "112 of 150 messages today": what Muse Spark has read for you today,
//  as a hairline track filling with ink, mustard once it matters (four
//  fifths gone), and when it comes back.
//

import SwiftUI

struct UsageBar: View {
    let used: Int
    let limit: Int
    var resetsAt: Date?

    @ScaledMetric(relativeTo: .subheadline) private var height: CGFloat = 8

    private var fraction: Double { limit > 0 ? min(1, Double(used) / Double(limit)) : 0 }
    private var left: Int { max(0, limit - used) }
    private var nearlyGone: Bool { fraction >= 0.8 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(used.formatted()) of \(limit.formatted()) messages today")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .monospacedDigit()
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.rule)
                    Capsule()
                        .fill(nearlyGone ? Theme.mustard : Theme.ink)
                        .frame(width: max(fraction > 0 ? height : 0, geometry.size.width * fraction))
                }
            }
            .frame(height: height)
            .motion(Motion.settle, value: fraction)
            .accessibilityHidden(true)
            Text(footnote)
                .font(.mono(.caption))
                .foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// "38 left · back at 12:00 AM".
    private var footnote: String {
        let back = resetsAt.map { " · back at \($0.formatted(date: .omitted, time: .shortened))" } ?? ""
        return left == 0 ? "None left today\(back)" : "\(left.formatted()) left\(back)"
    }
}
