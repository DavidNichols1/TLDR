//
//  AIStyle.swift
//  TLDR
//
//  The look every Muse Spark surface shares: the sparkle + gradient label,
//  the gradient pill button, and the washed, gradient-edged card.
//

import SwiftUI

/// "✦ Muse Spark" in the AI gradient.
struct AILabel: View {
    var text: String = Theme.aiName
    var font: Font = .caption.weight(.bold)

    var body: some View {
        Label(text, systemImage: Theme.aiSymbol)
            .font(font)
            .foregroundStyle(Theme.aiGradient)
    }
}

/// A gradient capsule with white text — "Catch me up", "Ask".
struct AIPillButtonStyle: ButtonStyle {
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(compact ? .subheadline.weight(.semibold) : .headline)
            .foregroundStyle(.white)
            .padding(.horizontal, compact ? 14 : 18)
            .padding(.vertical, compact ? 9 : 12)
            .background(Theme.aiGradient, in: Capsule())
            .shadow(color: Theme.violet.opacity(0.35), radius: configuration.isPressed ? 4 : 10, y: 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == AIPillButtonStyle {
    static var aiPill: AIPillButtonStyle { AIPillButtonStyle() }
    static var aiPillCompact: AIPillButtonStyle { AIPillButtonStyle(compact: true) }
}

extension View {
    /// A Muse Spark card: soft gradient wash and a thin gradient border.
    func aiCard(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.aiWash, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.aiDiagonal.opacity(0.45), lineWidth: 1)
            )
    }
}

/// A section heading inside an AI sheet.
struct AISectionHeader: View {
    let title: String
    let symbol: String
    var count: Int? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.aiGradient)
                .frame(width: 22)
            Text(title)
                .font(.headline)
            if let count, count > 0 {
                Text("\(count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}
