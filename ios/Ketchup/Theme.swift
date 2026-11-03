//
//  Theme.swift
//  Ketchup
//
//  A diner counter: cream paper, warm ink, ketchup red for the one thing to
//  press, mustard for marking what matters, pickle green for "confirmed".
//  No gradients, no sparkles, no glass. docs/DESIGN.md is the full guide;
//  the shapes and buttons built from these live in Design/.
//

import SwiftUI

enum Theme {

    // MARK: Paper and ink

    /// App background.
    static let cream = Color(light: 0xFBF5EA, dark: 0x17120F)
    /// Raised paper: cards, other people's bubbles.
    static let card = Color(light: 0xFFFDF8, dark: 0x231C17)
    /// Hairlines and card borders.
    static let rule = Color(light: 0xEADFCC, dark: 0x3A302A)
    /// Primary text, and my own bubbles.
    static let ink = Color(light: 0x2A1E19, dark: 0xF6EEE2)
    /// Secondary text.
    static let inkSoft = Color(light: 0x74655A, dark: 0xB3A595)
    /// Tertiary text and placeholders. Too faint for anything someone must read.
    static let inkFaint = Color(light: 0xA99A8C, dark: 0x7A6C60)
    /// Text on an ink fill.
    static let onInk = Color(light: 0xFFF8EE, dark: 0x17120F)

    // MARK: Condiments

    /// The brand red: the logo and the one button to press on a screen.
    static let ketchup = Color(light: 0xD7372B, dark: 0xE8473A)
    /// Small red text on cream (plain ketchup is too light to read small). Also the app tint.
    static let ketchupText = Color(light: 0xB22A20, dark: 0xFF7B6B)
    /// Text on a ketchup fill.
    static let onKetchup = Color(light: 0xFFF8EE, dark: 0xFFF8EE)
    /// The marker: highlights, unread badges, the jump-to-message glow.
    static let mustard = Color(light: 0xF3B33D, dark: 0xE9A92F)
    /// Text on a mustard fill, in both modes.
    static let onMustard = Color(light: 0x2A1E19, dark: 0x17120F)
    /// Confirmed stamps.
    static let pickle = Color(light: 0x4F7A3A, dark: 0x8CC07A)

    // MARK: People

    /// Name colors for people: brick, teal, plum, ochre, forest, navy, rose, slate.
    static let people: [Color] = [
        Color(light: 0xB4472E, dark: 0xF08A6E),
        Color(light: 0x1E6E6A, dark: 0x6FC2BA),
        Color(light: 0x7A3E73, dark: 0xD39BCB),
        Color(light: 0x9A6110, dark: 0xE8B25A),
        Color(light: 0x3C6B2F, dark: 0x93C784),
        Color(light: 0x2C4A86, dark: 0x8FAEE6),
        Color(light: 0xA63D57, dark: 0xEC96AB),
        Color(light: 0x4F5B66, dark: 0xA9B4BF),
    ]

    /// A stable color per person, for sender names and monograms.
    static func personColor(_ id: UUID) -> Color {
        let sum = id.uuidString.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return people[sum % people.count]
    }

    /// The same idea for places that only have a name (Muse Spark results).
    /// FNV-1a over the lowercased name; the salt (26) gives the demo chat's
    /// six people six different colors.
    static func personColor(name: String) -> Color {
        var hash: UInt64 = 0xcbf29ce484222325 ^ 26
        for byte in name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        hash ^= hash >> 32
        return people[Int(hash % UInt64(people.count))]
    }

    static func initials(_ name: String) -> String {
        let parts = name.split(whereSeparator: { $0 == " " || $0 == "." || $0 == "_" })
        let letters = parts.prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    // MARK: Muse Spark

    /// Credited in a byline ("Read by Muse Spark"), never with sparkles.
    static let modelName = "Muse Spark"

    // MARK: Old names
    // The screens still in the old purple look use these until they're
    // restyled. They map onto the new palette: gradients turn flat.

    @available(*, deprecated, message: "Use Theme.ketchup for the main button, Theme.ink for chat UI, Theme.ketchupText for small red text.")
    static let accent = ketchupText
    @available(*, deprecated, message: "No gradients. Use Theme.ketchup.")
    static let aiGradient = LinearGradient(colors: [ketchup, ketchup], startPoint: .leading, endPoint: .trailing)
    @available(*, deprecated, message: "No gradients. Use Theme.ink.")
    static let aiDiagonal = LinearGradient(colors: [ink, ink], startPoint: .topLeading, endPoint: .bottomTrailing)
    @available(*, deprecated, message: "Use paperCard() or Theme.card.")
    static let aiWash = LinearGradient(colors: [card, card], startPoint: .topLeading, endPoint: .bottomTrailing)
    @available(*, deprecated, message: "Use Theme.ketchupText.")
    static let indigo = ketchupText
    @available(*, deprecated, message: "Use Theme.ketchup.")
    static let violet = ketchup
    @available(*, deprecated, message: "Use Theme.ketchup.")
    static let pink = ketchup
    @available(*, deprecated, message: "No sparkles. Credit Muse Spark in a byline instead.")
    static let aiSymbol = "text.bubble"
    @available(*, deprecated, renamed: "modelName")
    static let aiName = modelName
}

// MARK: - Color

extension Color {
    /// A color that follows light and dark mode. Hex values are 0xRRGGBB.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor(light: light, dark: dark))
    }
}

extension UIColor {
    /// 0xRRGGBB. Nonisolated because UIKit resolves dynamic colors off the
    /// main thread too, and this target defaults to MainActor isolation.
    nonisolated convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }

    /// One hex value for light mode and one for dark.
    nonisolated convenience init(light: UInt32, dark: UInt32) {
        self.init { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        }
    }
}

// MARK: - Type

extension Font {
    /// New York: headlines, section titles, the wordmark.
    static func serif(_ style: Font.TextStyle, weight: Font.Weight = .bold) -> Font {
        .system(style, design: .serif, weight: weight)
    }

    /// SF Mono: times, amounts, codes, counts, kickers.
    static func mono(_ style: Font.TextStyle, weight: Font.Weight = .medium) -> Font {
        .system(style, design: .monospaced, weight: weight)
    }
}

// MARK: - Motion

/// How things move. Springs settle without bounce unless the user flicked or
/// checked something. With Reduce Motion on, swap in `fade` and opacity
/// transitions so nothing travels (`motion(_:value:)` and `.rise` do that).
enum Motion {
    /// The default for most changes.
    static let snappy = Animation.spring(duration: 0.3, bounce: 0)
    /// Bigger moves: content arriving, layout changes.
    static let settle = Animation.spring(duration: 0.45, bounce: 0)
    /// A little bounce, only for something the user flicked or checked.
    static let lively = Animation.spring(duration: 0.4, bounce: 0.2)
    /// Buttons going down and coming back up.
    static let press = Animation.spring(duration: 0.16, bounce: 0)
    /// The marker pass: quick start, long soft finish.
    static let sweep = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.5)
    /// The same curve slowed down, for the wordmark's squiggle drawing in.
    static let squirt = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.9)
    /// Seconds between items that arrive one after another.
    static let stagger: Double = 0.04
    /// What Reduce Motion gets instead: a short fade.
    static let fade = Animation.easeOut(duration: 0.2)

    /// `animation`, or `fade` when Reduce Motion is on.
    static func choose(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? fade : animation
    }

    /// `animation` delayed for the item at `index` in a list that staggers in.
    static func staggered(_ animation: Animation, index: Int) -> Animation {
        animation.delay(Double(index) * stagger)
    }
}

extension View {
    /// `.animation(_:value:)` that turns into `Motion.fade` with Reduce Motion on.
    func motion<V: Equatable>(_ animation: Animation = Motion.snappy, value: V) -> some View {
        modifier(MotionModifier(animation: animation, value: value))
    }
}

private struct MotionModifier<V: Equatable>: ViewModifier {
    let animation: Animation
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(Motion.choose(animation, reduceMotion: reduceMotion), value: value)
    }
}

extension AnyTransition {
    /// Rises 8 pt while fading in. Only fades with Reduce Motion on.
    static func rise(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 8))
    }
}

// MARK: - Dates

extension Date {
    /// Inbox stamp: "7:41 PM", "Yesterday", "Mon", "Oct 28".
    var inboxStamp: String {
        let cal = Calendar.current
        if cal.isDateInToday(self) { return formatted(date: .omitted, time: .shortened) }
        if cal.isDateInYesterday(self) { return "Yesterday" }
        if let days = cal.dateComponents([.day], from: self, to: .now).day, days < 7 {
            return formatted(.dateTime.weekday(.abbreviated))
        }
        return formatted(.dateTime.month(.abbreviated).day())
    }

    /// Day separator in a thread: "Today", "Yesterday", "Monday, Nov 2".
    var daySeparator: String {
        let cal = Calendar.current
        if cal.isDateInToday(self) { return "Today" }
        if cal.isDateInYesterday(self) { return "Yesterday" }
        return formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}
