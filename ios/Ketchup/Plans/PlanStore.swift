//
//  PlanStore.swift
//  Ketchup
//
//  Your plan as the server has it (my_plan(), migration 0010): the plan,
//  today's usage, and whether you've said yes to Muse Spark. Loaded at
//  sign-in (the hook in RootView), after a purchase (Purchases), and after a
//  catch-up the server turned down (PlanGate). Nothing here decides
//  anything: the server checks your OK and the allowance on every call.
//
//  Until migration 0010 is on the server there's no my_plan: `available`
//  stays false, the plan rows don't show and nothing asks for consent, so an
//  app built from this branch behaves as before against the old backend.
//

import Foundation
import Observation

@Observable
final class PlanStore {
    static let shared = PlanStore()

    private(set) var status: PlanStatus?
    /// The server has plans (migration 0010).
    private(set) var available = false
    /// You've said yes to Muse Spark, as the server last said (or since).
    private(set) var consented = false
    /// The last catch-up or question turned down for the allowance.
    private(set) var limitHit: PlanLimitHit?

    @ObservationIgnored private var user: UUID?
    @ObservationIgnored private var loading: Task<Void, Never>?

    var plan: PlanTier { status?.plan ?? .free }

    /// Signed in, or out: forgets the last person's plan, then asks for this one's.
    func signedIn(_ id: UUID?) async {
        guard id != user else { return }
        user = id
        status = nil
        limitHit = nil
        available = false
        consented = false
        guard id != nil else { return }
        await refresh()
        // A purchase the server hasn't seen (made on another device, or
        // while it couldn't answer) goes to it now.
        if available { await Purchases.shared.syncEntitlements() }
    }

    /// my_plan() again. Callers at the same time share one call.
    func refresh() async {
        if let loading { return await loading.value }
        let task = Task { await load() }
        loading = task
        await task.value
        loading = nil
    }

    /// Before a Muse Spark call, if nothing has loaded yet.
    func loadIfNeeded() async {
        if status == nil { await refresh() }
    }

    private func load() async {
        guard !Previewing.isOn else { return }
        do {
            apply(try await PlanAPI.myPlan())
        } catch {
            // "Could not find the function public.my_plan": not on the server yet.
            if error.localizedDescription.contains("my_plan") { available = false }
        }
    }

    func apply(_ fresh: PlanStatus) {
        status = fresh
        available = true
        consented = fresh.consentedAt != nil
    }

    func consentGiven() {
        consented = true
        status?.consentedAt = .now
    }

    /// The server said there's no consent (another phone withdrew it, or a
    /// stale copy): the next catch-up asks again.
    func consentMissing() {
        consented = false
        available = true
        status?.consentedAt = nil
    }

    func limitReached(_ hit: PlanLimitHit) {
        limitHit = hit
        guard var fresh = status, fresh.plan == hit.plan else { return }
        fresh.used = hit.used
        fresh.limit = hit.limit
        if let reset = hit.resetsAt { fresh.resetsAt = reset }
        status = fresh
    }

    #if DEBUG
    /// Offline previews: a plan and usage of their own, never the server's.
    func preview(_ status: PlanStatus?, hit: PlanLimitHit? = nil) {
        self.status = status
        limitHit = hit
        available = status != nil
        consented = status?.consentedAt != nil
    }
    #endif
}

/// The server calls behind plans.
enum PlanAPI {
    static func myPlan() async throws -> PlanStatus {
        let data = try await Supabase.shared.rpc("my_plan")
        return try JSON.decoder.decode(PlanStatus.self, from: data)
    }

    /// Your yes to Muse Spark, and that you're 18 or older (ai_consents; the
    /// server stamps the time). Saying it twice changes nothing.
    static func giveConsent() async throws {
        guard let me = Supabase.shared.userId else { throw APIError.notSignedIn }
        let row: [String: Any] = ["user_id": me.uuidString.lowercased(), "confirmed_adult": true]
        try await Supabase.shared.rest("POST", "/rest/v1/ai_consents",
                                       body: JSONSerialization.data(withJSONObject: row),
                                       prefer: "resolution=ignore-duplicates,return=minimal")
    }

    /// One StoreKit transaction to verify-purchase, which checks Apple's
    /// signature and sets the plan.
    static func verify(jws: String) async throws -> PurchaseAnswer {
        let data = try await Supabase.shared.function("verify-purchase", ["jws": jws])
        return try JSON.decoder.decode(PurchaseAnswer.self, from: data)
    }
}
