//
//  PaywallView.swift
//  Ketchup
//
//  The plans, as three cards on the counter: Free, Plus and Pro, each with
//  its daily allowance and its renewal price as the biggest number on it.
//  Opened from Settings' "Your plan" (pushed), or over a catch-up the
//  server turned down for today's allowance (PaywallSheet, from PlanGate),
//  which then says what happened first. The one ketchup button is the plan
//  worth getting next. Restore purchases and the terms sit under the cards,
//  as Apple asks of a subscription screen.
//

import SwiftUI

struct PaywallView: View {
    /// The catch-up or question the server just turned down, if that's why it opened.
    var hit: PlanLimitHit?
    /// Closes the sheet this sits in (nil when pushed in Settings).
    var close: (() -> Void)?

    private var store: PlanStore { .shared }
    private var purchases: Purchases { .shared }

    private var current: PlanTier { store.plan }

    /// The plan the ketchup button goes to: the next one up, or whichever
    /// would have had room for what was just turned down.
    private var suggested: PlanTier? {
        if let hit { return hit.suggested > current ? hit.suggested : nil }
        switch current {
        case .free: return .plus
        case .plus: return .pro
        case .pro: return nil
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if let bought = purchases.bought {
                    boughtCard(bought)
                } else if let hit {
                    turnedDown(hit)
                }
                ForEach(PlanTier.allCases) { tier in
                    card(tier)
                }
                if let note = purchases.note {
                    Text(note)
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .paperCard(padding: 14)
                        .transition(.opacity)
                }
                small
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 36)
            .motion(Motion.settle, value: purchases.bought)
            .motion(Motion.fade, value: purchases.note)
        }
        .background(Theme.cream)
        .task { await purchases.loadProducts() }
        .sensoryFeedback(.success, trigger: purchases.bought) { _, now in now != nil }
    }

    // MARK: Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Kicker("Plans")
            Text("More catch-ups a day")
                .font(.serif(.largeTitle))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("\(Theme.modelName) reads your chats so you don't have to. A plan sets how many messages it reads for you each day.")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// What the server said, with today's bar.
    private func turnedDown(_ hit: PlanLimitHit) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Kicker("Today", color: Theme.ketchupText)
            Text(hit.error)
                .font(.serif(.title3))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            UsageBar(used: hit.used, limit: hit.limit, resetsAt: hit.resetsAt)
        }
        .paperCard()
    }

    private func boughtCard(_ tier: PlanTier) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Kicker("Done")
                Spacer()
                Stamp(tier.name)
            }
            Text("You're on \(tier.name): \(tier.dailyMessages.formatted()) messages a day, starting now.")
                .font(.serif(.title3))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let close {
                Button("Back to my catch-up", action: close)
                    .buttonStyle(.ink(.compact))
            }
        }
        .paperCard()
    }

    private func card(_ tier: PlanTier) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(tier.name)
                    .font(.serif(.title2))
                    .foregroundStyle(Theme.ink)
                MenuLeader()
                    .accessibilityHidden(true)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(purchases.price(tier))
                        .font(.mono(.title2, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    if tier != .free {
                        Text("a month")
                            .font(.mono(.caption))
                            .foregroundStyle(Theme.inkSoft)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                perk("text.bubble", "\(tier.dailyMessages.formatted()) messages a day")
                if tier.listens {
                    perk("speaker.wave.2", "Listen: catch-ups read aloud on your phone")
                }
                if tier == .free {
                    perk("checkmark", "Catch me up and Ask the chat")
                }
            }
            if tier == current {
                Stamp("Your plan", tilt: -3)
                    .padding(.top, 2)
            } else if tier != .free && tier > current {
                buyButton(tier)
            }
        }
        .paperCard()
        .accessibilityElement(children: .contain)
    }

    private func perk(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.inkSoft)
        }
    }

    @ViewBuilder
    private func buyButton(_ tier: PlanTier) -> some View {
        let busy = purchases.buying == tier
        let button = Button {
            Task { await purchases.buy(tier) }
        } label: {
            HStack(spacing: 8) {
                if busy { ProgressView().tint(tier == suggested ? Theme.onKetchup : Theme.ink) }
                Text(busy ? "Opening the App Store" : current == .free ? "Get \(tier.name)" : "Switch to \(tier.name)")
            }
        }
        .disabled(purchases.buying != nil)
        if tier == suggested {
            button.buttonStyle(.ketchup)
        } else {
            button.buttonStyle(.outline)
        }
    }

    /// The small print: what every plan shares, how a subscription renews,
    /// Restore, and the terms.
    private var small: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Every plan uses Meta's Standard mode, which Meta doesn't train on. A catch-up counts the messages it reads and a question the messages it searches, at least 10 each.\(resetLine)")
                .font(.footnote)
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            Text("Plus and Pro renew every month until you cancel. Payment goes to your Apple Account when you confirm, and you can cancel any time, at least a day before it renews, in Settings, under your name, then Subscriptions.")
                .font(.footnote)
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button {
                    Task { await purchases.restore() }
                } label: {
                    HStack(spacing: 6) {
                        if purchases.restoring { ProgressView().tint(Theme.ink) }
                        Text("Restore purchases")
                    }
                }
                .buttonStyle(.outline(.compact))
                .disabled(purchases.restoring || purchases.buying != nil)
                Link("Terms of Use", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ketchupText)
            }
        }
    }

    /// " Your messages come back at 12:00 AM."
    private var resetLine: String {
        guard let reset = store.status?.resetsAt ?? hit?.resetsAt else { return "" }
        return " Your messages come back at \(reset.formatted(date: .omitted, time: .shortened))."
    }
}

/// The dotted line between a dish and its price on a diner menu.
private struct MenuLeader: View {
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                path.move(to: CGPoint(x: 0, y: geometry.size.height - 1))
                path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height - 1))
            }
            .stroke(Theme.inkFaint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [0.5, 5]))
        }
        .frame(minWidth: 12, maxHeight: 10)
    }
}

/// The paywall over a catch-up: the plans, under a bar with Done.
struct PaywallSheet: View {
    var hit: PlanLimitHit?
    let close: () -> Void

    var body: some View {
        PaywallView(hit: hit, close: close)
            .safeAreaInset(edge: .top, spacing: 0) {
                SheetBar(title: "Ketchup plans") { close() }
            }
            .background(Theme.cream)
            .presentationBackground(Theme.cream)
            .presentationDragIndicator(.visible)
    }
}
