//
//  Labels.swift
//  Ketchup
//
//  Small type pieces: kickers over headlines, section titles with a count,
//  people's monograms, and the rubber stamp for plans.
//

import SwiftUI

/// A small mono label over a headline or a card: "FOR YOU", "SAT 6:00 AM",
/// "READ BY MUSE SPARK". VoiceOver reads the original casing.
struct Kicker: View {
    let text: String
    var color: Color

    init(_ text: String, color: Color = Theme.inkSoft) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.mono(.caption2, weight: .semibold))
            .textCase(.uppercase)
            .tracking(1.4)
            .foregroundStyle(color)
    }
}

/// A section heading in New York, with a faint count after it ("Plans 6").
/// Marked as a header for VoiceOver.
struct SectionTitle: View {
    let title: String
    var count: Int?

    init(_ title: String, count: Int? = nil) {
        self.title = title
        self.count = count
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.serif(.title3))
                .foregroundStyle(Theme.ink)
            if let count {
                Text("\(count)")
                    .font(.mono(.footnote))
                    .foregroundStyle(Theme.inkFaint)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A person's initials on a soft tile of their color: rows, member lists,
/// "who's going". A rounded square, not a circle, so it reads as paper.
/// Decorative, so VoiceOver skips it; say the name in the row instead.
/// Pass a `size` from `@ScaledMetric` where text sits beside it.
struct Monogram: View {
    let name: String
    var color: Color
    var size: CGFloat

    init(name: String, color: Color? = nil, size: CGFloat = 36) {
        self.name = name
        self.color = color ?? Theme.personColor(name: name)
        self.size = size
    }

    var body: some View {
        Text(Theme.initials(name))
            .font(.system(size: size * 0.4, weight: .semibold, design: .serif))
            .foregroundStyle(color)
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .frame(width: size, height: size)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A rubber stamp, tilted a few degrees: "CONFIRMED" in pickle green on a
/// plan ticket, or another word in another color ("MAYBE" in inkSoft).
struct Stamp: View {
    let text: String
    var color: Color
    var tilt: Double

    init(_ text: String, color: Color = Theme.pickle, tilt: Double = -4) {
        self.text = text
        self.color = color
        self.tilt = tilt
    }

    var body: some View {
        Text(text)
            .font(.mono(.caption2, weight: .bold))
            .textCase(.uppercase)
            .tracking(1.2)
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(color, lineWidth: 1.5)
            }
            .rotationEffect(.degrees(tilt))
    }
}
