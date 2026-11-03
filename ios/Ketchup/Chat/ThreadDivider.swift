//
//  ThreadDivider.swift
//  Ketchup
//
//  The lines between bubbles: a day ("YESTERDAY") as a mono kicker, the
//  start of what's new ("302 NEW") on a mustard mark between hairlines, and
//  who joined ("Maya joined").
//

import SwiftUI

/// Someone joined the chat: "Maya joined", small and centered like a day
/// line, the name in their chat color ("You joined" in ink). The server
/// writes one when someone joins, starts the chat or is added (0009).
struct JoinedLine: View {
    let name: String
    let color: Color

    var body: some View {
        Text("\(Text(name).fontWeight(.semibold).foregroundStyle(color)) joined")
            .font(.footnote)
            .foregroundStyle(Theme.inkSoft)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(name) joined")
    }
}

/// A day in the thread: "TODAY", "YESTERDAY", "MONDAY, NOV 2".
struct ThreadDivider: View {
    let text: String

    var body: some View {
        Kicker(text)
            .frame(maxWidth: .infinity)
            .padding(.top, 18)
            .padding(.bottom, 6)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Where the unread part starts. The mark is full mustard with dark
/// `onMustard` type in both modes (a dimmed mark under light type reads
/// muddy in dark mode). It sweeps in when it first shows, and is simply
/// there with Reduce Motion on.
struct UnreadDivider: View {
    let count: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0

    var body: some View {
        HStack(spacing: 12) {
            hairline
            Text("\(count) new")
                .font(.mono(.caption2, weight: .bold))
                .textCase(.uppercase)
                .tracking(1.4)
                .foregroundStyle(Theme.onMustard)
                .fixedSize()
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background {
                    MarkerStroke(progress: progress)
                        .fill(Theme.mustard)
                }
            hairline
        }
        .padding(.vertical, 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(count == 1 ? "1 new message" : "\(count) new messages")
        .onAppear {
            guard progress < 1 else { return }
            if reduceMotion {
                progress = 1
            } else {
                withAnimation(Motion.sweep.delay(0.2)) { progress = 1 }
            }
        }
    }

    private var hairline: some View {
        Rectangle()
            .fill(Theme.rule)
            .frame(height: 1)
    }
}
