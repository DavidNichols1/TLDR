//
//  AISheetParts.swift
//  Ketchup
//
//  What the two Muse Spark sheets share: the bar across the top, the byline
//  that credits Muse Spark, the cards for a failed call and for nothing
//  new (with no catch-up kept, or over the last one), and how a page's
//  sections arrive.
//

import SwiftUI

/// Pinned across the top of a Muse Spark sheet: the chat's name as a
/// running head, and Done. A hairline shows once the page scrolls under it.
struct SheetBar: View {
    let title: String
    var scrolled = false
    let done: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Kicker(title)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button(action: done) {
                Text("Done")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .padding(.vertical, 10)
                    .padding(.leading, 12)
            }
            .buttonStyle(.pressable)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .background(Theme.cream)
        .overlay(alignment: .bottom) {
            Theme.rule
                .frame(height: 1)
                .opacity(scrolled ? 1 : 0)
                .motion(Motion.fade, value: scrolled)
        }
    }
}

/// Credits Muse Spark the way a paper credits a writer: "Read by Muse Spark
/// · 302 messages · 23 s". Small and mono.
struct MuseByline: View {
    /// "Read by", "Answered by".
    let verb: String
    var details: [String] = []

    var body: some View {
        let rest = details.map { " · \($0)" }.joined()
        Text("\(Text(verbatim: verb)) \(Text(verbatim: Theme.modelName).fontWeight(.semibold).foregroundStyle(Theme.ink))\(Text(verbatim: rest))")
            .font(.mono(.caption))
            .foregroundStyle(Theme.inkSoft)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// "302 messages" and how long it took ("23 s"), or "Saved" for a
    /// catch-up Muse Spark had already made.
    static func details<R: Decodable>(_ response: BriefResponse<R>) -> [String] {
        var parts: [String] = []
        if let count = response.messageCount, count > 0 {
            parts.append(count == 1 ? "1 message" : "\(count.formatted()) messages")
        }
        if response.cached == true {
            parts.append("Saved")
        } else if let ms = response.latencyMs, ms > 0 {
            parts.append("\(max(1, Int((Double(ms) / 1000).rounded()))) s")
        }
        return parts
    }
}

/// A Muse Spark call that didn't come back: what happened in plain words,
/// and a way to try again. `prominent` makes Try again the screen's one
/// ketchup button; Ask keeps that for its own Ask button.
struct AIErrorCard: View {
    let message: String
    /// A line of reassurance under the message ("Nothing was marked as read.").
    var note: String? = nil
    var prominent = true
    let retry: () -> Void

    var body: some View {
        let parts = Sentences.first(message)
        // "Try again." under a Try again button says it twice.
        let rest = parts.rest.flatMap { $0.lowercased().hasPrefix("try again.") && $0.count <= 10 ? nil : $0 }
        let more = [rest, note].compactMap { $0 }.joined(separator: " ")
        VStack(alignment: .leading, spacing: 16) {
            Kicker("Didn't go through", color: Theme.ketchupText)
            VStack(alignment: .leading, spacing: 6) {
                Text(parts.first)
                    .font(.serif(.title3))
                    .foregroundStyle(Theme.ink)
                if !more.isEmpty {
                    Text(more)
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSoft)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            if prominent {
                Button("Try again", action: retry)
                    .buttonStyle(.ketchup)
            } else {
                Button("Try again", action: retry)
                    .buttonStyle(.ink(.compact))
            }
        }
        .paperCard(padding: 20)
    }
}

/// Nothing unread to catch up on: the drop, and a line saying so.
struct CaughtUpCard: View {
    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                KetchupDrop().fill(Theme.ketchup)
                DropShine().fill(Theme.onKetchup.opacity(0.9))
            }
            .frame(width: 72, height: 72)
            .padding(.bottom, 6)
            .accessibilityHidden(true)
            Text("You're all caught up")
                .font(.serif(.title2))
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            Text("Nothing new to catch up on since you last read this chat. Looking for something? Try Ask the chat.")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSoft)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 56)
    }
}

/// Over the last catch-up kept on the phone, when there's nothing new to
/// read: "Nothing new since 2:14 PM. Here's your last catch-up." If people
/// wrote after it and you've read them since, it says that instead.
struct NothingNewNote: View {
    /// When the catch-up was kept.
    let since: Date
    /// Someone wrote after it, and it's all read.
    var readSince = false

    @State private var shown = false
    @ScaledMetric(relativeTo: .headline) private var drop: CGFloat = 24

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            KetchupDrop()
                .fill(Theme.ketchup)
                .frame(width: drop, height: drop)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(headline)
                    .font(.serif(.headline))
                    .foregroundStyle(Theme.ink)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSoft)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .paperCard(padding: 16)
        .accessibilityElement(children: .combine)
        .riseIn(shown, index: 0)
        .onAppear { shown = true }
    }

    private var headline: String {
        readSince ? "Nothing unread." : "Nothing new since \(since.sinceStamp)."
    }

    private var detail: String {
        readSince ? "Here's your last catch-up, from \(since.sinceStamp)." : "Here's your last catch-up."
    }
}

extension View {
    /// Rises into place `index` beats after `shown` turns on (plus `after`
    /// seconds), for a page's sections arriving once. Only fades with Reduce
    /// Motion on.
    func riseIn(_ shown: Bool, index: Int, after delay: Double = 0) -> some View {
        modifier(RiseIn(shown: shown, index: index, delay: delay))
    }
}

private struct RiseIn: ViewModifier {
    let shown: Bool
    let index: Int
    let delay: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 16)
            .animation(Motion.choose(Motion.settle, reduceMotion: reduceMotion)
                .delay(Double(index) * Motion.stagger + delay), value: shown)
    }
}
