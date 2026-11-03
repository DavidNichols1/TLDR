//
//  Buttons.swift
//  Ketchup
//
//  Button styles: .ketchup for the one thing to press on a screen, .ink and
//  .outline for everything else, .pressable for tappable cards and rows.
//

import SwiftUI

/// A capsule button. `.ketchup` is the screen's main action and gives a
/// light tap of haptics as it goes down; `.ink` is a strong second choice,
/// `.outline` a quiet one. Large ones fill the width; `.compact` hugs its
/// label, for buttons inside cards ("Add to calendar", "Try again").
struct CapsuleButtonStyle: ButtonStyle {
    enum Fill { case ketchup, ink, outline }
    enum Size { case large, compact }

    var fill: Fill
    var size: Size = .large

    func makeBody(configuration: Configuration) -> some View {
        CapsuleButton(configuration: configuration, fill: fill, size: size)
    }
}

/// The style's body as a view of its own, so it can read `isEnabled`.
private struct CapsuleButton: View {
    let configuration: ButtonStyleConfiguration
    let fill: CapsuleButtonStyle.Fill
    let size: CapsuleButtonStyle.Size

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let pressed = configuration.isPressed
        configuration.label
            .font(size == .large ? .headline : .subheadline.weight(.semibold))
            .foregroundStyle(labelColor)
            .multilineTextAlignment(.center)
            .padding(.horizontal, size == .large ? 22 : 16)
            .padding(.vertical, size == .large ? 15 : 9)
            .frame(maxWidth: size == .large ? .infinity : nil)
            .background { capsule }
            .contentShape(Capsule())
            .opacity(isEnabled ? (pressed && reduceMotion ? 0.7 : 1) : 0.4)
            .scaleEffect(pressed && !reduceMotion ? 0.97 : 1)
            .animation(Motion.press, value: pressed)
            .sensoryFeedback(.impact(weight: .light), trigger: pressed) { _, down in
                down && fill == .ketchup
            }
    }

    private var labelColor: Color {
        switch fill {
        case .ketchup: Theme.onKetchup
        case .ink: Theme.onInk
        case .outline: Theme.ink
        }
    }

    @ViewBuilder private var capsule: some View {
        switch fill {
        case .ketchup: Capsule().fill(Theme.ketchup)
        case .ink: Capsule().fill(Theme.ink)
        case .outline: Capsule().strokeBorder(Theme.ink, lineWidth: 1)
        }
    }
}

extension ButtonStyle where Self == CapsuleButtonStyle {
    /// The one thing to press on a screen: a full-width red capsule.
    static var ketchup: CapsuleButtonStyle { CapsuleButtonStyle(fill: .ketchup) }
    /// A strong second action: an ink capsule.
    static var ink: CapsuleButtonStyle { CapsuleButtonStyle(fill: .ink) }
    /// A quiet action: a hairline ink capsule.
    static var outline: CapsuleButtonStyle { CapsuleButtonStyle(fill: .outline) }

    static func ketchup(_ size: CapsuleButtonStyle.Size) -> CapsuleButtonStyle {
        CapsuleButtonStyle(fill: .ketchup, size: size)
    }
    static func ink(_ size: CapsuleButtonStyle.Size) -> CapsuleButtonStyle {
        CapsuleButtonStyle(fill: .ink, size: size)
    }
    static func outline(_ size: CapsuleButtonStyle.Size) -> CapsuleButtonStyle {
        CapsuleButtonStyle(fill: .outline, size: size)
    }
}

/// For things that already look tappable (a card, a row, a chip): they give
/// a little as you press. With Reduce Motion they dim instead of shrinking.
struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        PressableBody(configuration: configuration, scale: scale)
    }
}

private struct PressableBody: View {
    let configuration: ButtonStyleConfiguration
    let scale: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let pressed = configuration.isPressed
        configuration.label
            .contentShape(.rect)
            .opacity(pressed && reduceMotion ? 0.7 : 1)
            .scaleEffect(pressed && !reduceMotion ? scale : 1)
            .animation(Motion.press, value: pressed)
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    /// Scale only, for tappable cards and rows.
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}
