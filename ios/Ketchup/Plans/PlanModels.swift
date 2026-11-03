//
//  PlanModels.swift
//  Ketchup
//
//  Ketchup's plans: how many messages Muse Spark reads for you a day. The
//  server decides (plan_limit() in migration 0010, checked on every call);
//  these are the same numbers for the plan cards, which show before the
//  server answers. Every plan uses Meta's Standard mode, which Meta doesn't
//  train on, so the plans differ in the allowance, and Pro reads catch-ups
//  aloud on the phone.
//

import Foundation

nonisolated enum PlanTier: String, Codable, CaseIterable, Identifiable, Comparable, Sendable {
    case free, plus, pro

    var id: String { rawValue }

    var name: String {
        switch self {
        case .free: "Free"
        case .plus: "Plus"
        case .pro: "Pro"
        }
    }

    /// Messages Muse Spark reads a day: plan_limit() in migration 0010.
    var dailyMessages: Int {
        switch self {
        case .free: 150
        case .plus: 400
        case .pro: 1000
        }
    }

    /// The App Store subscription (Ketchup.storekit, App Store Connect).
    var productID: String? {
        switch self {
        case .free: nil
        case .plus: "com.vibetemp.ketchup.plus.monthly"
        case .pro: "com.vibetemp.ketchup.pro.monthly"
        }
    }

    /// The price until the App Store says (its own wins: the local currency).
    var listPrice: String {
        switch self {
        case .free: "$0"
        case .plus: "$4.99"
        case .pro: "$9.99"
        }
    }

    /// Pro reads catch-ups aloud with the phone's own voice.
    var listens: Bool { self == .pro }

    static func forProduct(_ id: String) -> PlanTier? { allCases.first { $0.productID == id } }

    static var productIDs: [String] { allCases.compactMap(\.productID) }

    /// The cheapest plan with room for `messages` a day.
    static func covering(_ messages: Int) -> PlanTier {
        allCases.first { $0.dailyMessages >= messages } ?? .pro
    }

    private var rank: Int {
        switch self {
        case .free: 0
        case .plus: 1
        case .pro: 2
        }
    }

    static func < (a: PlanTier, b: PlanTier) -> Bool { a.rank < b.rank }
}

/// my_plan(): your plan, today's usage, and your OK for Muse Spark.
nonisolated struct PlanStatus: Decodable, Equatable, Sendable {
    var plan: PlanTier
    /// app_store, sandbox, xcode-test or manual; nil on Free.
    var source: String?
    var productId: String?
    var expiresAt: Date?
    var used: Int
    var limit: Int
    /// The next midnight in Denver, when the day's allowance comes back.
    var resetsAt: Date?
    var voice: Bool
    var consentedAt: Date?

    var left: Int { max(0, limit - used) }

    enum CodingKeys: String, CodingKey {
        case plan, source, used, limit, voice
        case productId = "product_id"
        case expiresAt = "expires_at"
        case resetsAt = "resets_at"
        case consentedAt = "consented_at"
    }
}

/// A catch-up or question turned down for today's allowance: the 402 from
/// catch-up and catch-up-text (supabase/functions/_shared/plan.ts).
nonisolated struct PlanLimitHit: Decodable, Equatable, Identifiable, Sendable {
    /// The sentence to show: "You've used today's 150 free messages."
    let error: String
    let plan: PlanTier
    let used: Int
    let limit: Int
    /// What this call would have counted.
    let needed: Int
    let resetsAt: Date?

    var id: String { "\(plan.rawValue)-\(used)-\(needed)" }

    /// The plan to suggest: the cheapest one up that would have had room.
    var suggested: PlanTier {
        let next: PlanTier = plan == .free ? .plus : .pro
        return max(next, PlanTier.covering(used + needed))
    }

    enum CodingKeys: String, CodingKey {
        case error, plan, used, limit, needed
        case resetsAt = "resets_at"
    }
}

/// verify-purchase's answer: what happened, and the plan now.
nonisolated struct PurchaseAnswer: Decodable, Sendable {
    /// applied, stale, expired, upgraded or revoked.
    let result: String
    let source: String?
    let plan: PlanStatus?
}
