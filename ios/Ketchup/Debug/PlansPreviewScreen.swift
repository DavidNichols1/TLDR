//
//  PlansPreviewScreen.swift
//  Ketchup
//
//  Plans on fixtures, one screen per `-screen` name: the paywall on Free
//  with 112 of 150 used; Settings with "Your plan" and the usage bar; a
//  catch-up of the 302-message Breck chat turned down on Free, with the
//  paywall over it; the one-time consent sheet over a catch-up; and a Pro
//  catch-up with Listen. Offline like every preview: nothing reaches the
//  server. Add `-storekitTest YES` (simulator) and the paywall's buttons
//  buy through Xcode's local StoreKit test (Plans/StoreKitTesting.swift).
//

#if DEBUG
import SwiftUI

struct PlansPreviewScreen: View {
    enum Screen: String, CaseIterable {
        case paywall
        case freeUsage = "plan-free-usage"
        case limitHit = "plan-limit-hit"
        case consent
        case listen = "plan-listen"
    }

    static var names: [String] { Screen.allCases.map(\.rawValue) }

    let name: String
    @State private var app = PreviewData.app()
    @State private var model: ChatModel

    init(name: String) {
        self.name = name
        let screen = Screen(rawValue: name)
        switch screen {
        case .limitHit:
            _model = State(initialValue: PreviewData.chatModel(catchUp: .failed(Self.hit.error), delay: .seconds(0.2)))
            PlanStore.shared.preview(Self.status(.free, used: 112), hit: Self.hit)
        case .consent:
            _model = State(initialValue: PreviewData.chatModel(catchUp: .loading))
            PlanStore.shared.preview(Self.status(.free, used: 0, consented: false))
        case .listen:
            _model = State(initialValue: PreviewData.chatModel(delay: .zero))
            PlanStore.shared.preview(Self.status(.pro, used: 302))
        case .paywall, .freeUsage, nil:
            _model = State(initialValue: PreviewData.chatModel())
            PlanStore.shared.preview(Self.status(.free, used: 112))
        }
        PeopleStore.shared.preview(blocked: [])
    }

    var body: some View {
        Group {
            switch Screen(rawValue: name) {
            case .paywall:
                PaywallSheet {}
                    .task { await Self.buyIfAsked() }
            case .freeUsage:
                SettingsView { _ in }
            case .limitHit:
                CatchUpSheet(model: model, refs: refs)
                    .sheet(isPresented: .constant(true)) {
                        PaywallSheet(hit: Self.hit) {}
                    }
            case .consent:
                CatchUpSheet(model: model, refs: refs)
                    .sheet(isPresented: .constant(true)) {
                        AIConsentSheet { _ in }
                    }
            case .listen:
                CatchUpSheet(model: model, refs: refs)
            case nil:
                PreviewIndex(unknown: name)
            }
        }
        .environment(app)
    }

    private var refs: RefContext {
        RefContext(preview: { [model] in model.preview($0) }, jump: { _ in })
    }

    /// `-buy plus` (or pro): presses that plan's button 1.5 s in, as a tap
    /// would. With `-storekitTest YES` it goes through Xcode's local StoreKit
    /// test: its purchase sheet, or straight through with `-storekitDialogs NO`.
    private static func buyIfAsked() async {
        guard let raw = UserDefaults.standard.string(forKey: "buy"), let tier = PlanTier(rawValue: raw) else { return }
        try? await Task.sleep(for: .seconds(1.5))
        await Purchases.shared.buy(tier)
    }

    // MARK: Fixtures

    /// The next midnight in Denver, when the allowance comes back.
    private static var midnight: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Denver") ?? .current
        return calendar.nextDate(after: .now, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime) ?? .now
    }

    static func status(_ plan: PlanTier, used: Int, consented: Bool = true) -> PlanStatus {
        PlanStatus(plan: plan, source: plan == .free ? nil : "app_store", productId: plan.productID,
                   expiresAt: plan == .free ? nil : .now.addingTimeInterval(20 * 86_400),
                   used: used, limit: plan.dailyMessages, resetsAt: midnight, voice: plan == .pro,
                   consentedAt: consented ? .now.addingTimeInterval(-86_400) : nil)
    }

    /// What catch-up says on Free with 112 used, for Breck's 302 unread
    /// (supabase/functions/_shared/plan.ts, word for word).
    static let hit = PlanLimitHit(
        error: "This catch-up reads 302 messages. Free covers 150 a day, and you have 38 left today.",
        plan: .free, used: 112, limit: 150, needed: 302, resetsAt: midnight)
}
#endif
