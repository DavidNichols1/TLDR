//
//  CatchUpBar.swift
//  Ketchup
//
//  Pinned under the chat's title: the big ketchup "Catch me up · 302 new"
//  button while there's something to catch up on, and "Ask" always. Once
//  the background catch-up has landed, the count quietly adds "ready".
//  With nothing unread, "Your catch-up" reopens the last one (this visit's,
//  or the one kept on the phone).
//

import SwiftUI

struct CatchUpBar: View {
    let unread: Int
    /// A finished catch-up exists and can be reopened.
    let hasBrief: Bool
    /// A catch-up is kept on the phone (Saved/), to show again when
    /// nothing's unread.
    var hasKept = false
    let onCatchUp: () -> Void
    let onAsk: () -> Void

    @ScaledMetric(relativeTo: .headline) private var dropSize: CGFloat = 18

    /// The prefetched catch-up is in, so the tap opens it straight away.
    private var ready: Bool { unread > 0 && hasBrief }

    var body: some View {
        HStack(spacing: 10) {
            if unread > 0 {
                Button(action: onCatchUp) {
                    HStack(spacing: 12) {
                        drop(Theme.onKetchup)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Catch me up")
                            count
                                .font(.mono(.caption))
                        }
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.ketchup)
                .accessibilityLabel("Catch me up")
                .accessibilityValue(ready ? "\(unread) new messages, ready" : "\(unread) new messages")
                .transition(.opacity)
            } else if hasBrief || hasKept {
                Button(action: onCatchUp) {
                    Label {
                        Text("Your catch-up")
                    } icon: {
                        drop(Theme.ketchup)
                    }
                }
                .buttonStyle(.outline(.compact))
            }

            if unread == 0 { Spacer(minLength: 0) }

            Button(action: onAsk) {
                Label(unread > 0 ? "Ask" : "Ask the chat", systemImage: "questionmark.bubble")
                    .frame(maxHeight: .infinity)
            }
            .buttonStyle(.outline(.compact))
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.cream)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.rule).frame(height: 1)
        }
        .motion(Motion.settle, value: unread)
        .motion(Motion.fade, value: ready)
    }

    /// "302 new", then "302 new · ready" once the prefetch is in. It sits on
    /// its own line under the title, so the button never changes size.
    private var count: some View {
        Text(ready ? "\(unread) new · ready" : "\(unread) new")
            .lineLimit(1)
            .contentTransition(.opacity)
    }

    private func drop(_ color: Color) -> some View {
        KetchupDrop()
            .fill(color)
            .frame(width: dropSize, height: dropSize)
            .accessibilityHidden(true)
    }
}
