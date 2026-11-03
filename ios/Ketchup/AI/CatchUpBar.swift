//
//  CatchUpBar.swift
//  Ketchup
//
//  Pinned under the chat's title: the big "Catch me up · N unread" button
//  while there's something to catch up on, and "Ask the chat" always.
//

import SwiftUI

struct CatchUpBar: View {
    let unread: Int
    /// A finished catch-up exists and can be reopened.
    let hasBrief: Bool
    let onCatchUp: () -> Void
    let onAsk: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if unread > 0 {
                Button(action: onCatchUp) {
                    HStack(spacing: 8) {
                        Image(systemName: Theme.aiSymbol)
                            .symbolEffect(.pulse, options: .repeating)
                        Text("Catch me up")
                        Text("· \(unread) unread")
                            .fontWeight(.regular)
                            .opacity(0.9)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.aiPill)
                .transition(.scale.combined(with: .opacity))
            } else if hasBrief {
                Button(action: onCatchUp) {
                    Label("Your catch-up", systemImage: Theme.aiSymbol)
                }
                .buttonStyle(.aiPillCompact)
            }

            if unread == 0 { Spacer(minLength: 0) }

            Button(action: onAsk) {
                Label(unread > 0 ? "Ask" : "Ask the chat", systemImage: "questionmark.bubble")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.aiGradient)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.aiGradient.opacity(0.6), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .animation(.spring(duration: 0.4), value: unread)
    }
}
