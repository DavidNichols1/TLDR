//
//  Purchases.swift
//  Ketchup
//
//  Plus and Pro through the App Store (StoreKit 2): the two products,
//  buying one, Restore, and every transaction StoreKit hands over (a
//  purchase, a renewal, one bought on another device). Each one goes to the
//  verify-purchase edge function, which checks Apple's signature and sets
//  the plan: the app never sets its own. A purchase carries the account's id
//  as its appAccountToken, so the server knows whose it is.
//
//  A transaction is finished only once the server has it, so StoreKit keeps
//  handing over any the server hasn't seen (Transaction.updates at launch).
//
//  Testing: Ketchup.storekit is Xcode's local StoreKit test, wired into the
//  scheme (Run > Options). Those purchases are free, signed by Xcode instead
//  of Apple, and the server only takes them while STOREKIT_XCODE_TEST=true.
//  Without Xcode attached, `-storekitTest YES` turns the same file on in a
//  simulator DEBUG build (StoreKitTesting.swift).
//

import StoreKit
import Observation

@Observable
final class Purchases {
    static let shared = Purchases()

    private(set) var products: [PlanTier: Product] = [:]
    /// The plan being bought right now.
    private(set) var buying: PlanTier?
    private(set) var restoring = false
    /// What the last purchase or restore came to, when it isn't simply done.
    var note: String?
    /// The plan just bought, once the server has it.
    private(set) var bought: PlanTier?

    @ObservationIgnored private var listener: Task<Void, Never>?

    /// At launch: listen for transactions, and load the products.
    func start() {
        guard listener == nil else { return }
        #if DEBUG && targetEnvironment(simulator)
        StoreKitTesting.startIfAsked()
        #endif
        listener = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.send(update, quietly: true)
            }
        }
        Task { await loadProducts() }
    }

    func loadProducts() async {
        guard products.isEmpty else { return }
        guard let found = try? await Product.products(for: PlanTier.productIDs) else { return }
        for product in found {
            if let tier = PlanTier.forProduct(product.id) { products[tier] = product }
        }
    }

    /// "$4.99" as the App Store says it, or the list price until it does.
    func price(_ tier: PlanTier) -> String {
        products[tier]?.displayPrice ?? tier.listPrice
    }

    func buy(_ tier: PlanTier) async {
        guard buying == nil, tier != .free else { return }
        guard let account = Self.account else {
            note = "Sign in to Cetchup first."
            return
        }
        note = nil
        bought = nil
        buying = tier
        defer { buying = nil }
        if products[tier] == nil { await loadProducts() }
        guard let product = products[tier] else {
            note = "The App Store isn't answering. Try again in a moment."
            return
        }
        do {
            switch try await product.purchase(options: [.appAccountToken(account)]) {
            case .success(let result):
                await send(result, quietly: false, buying: tier)
            case .pending:
                note = "Waiting for approval. Your plan changes once it's approved."
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            note = "The purchase didn't go through. \(error.localizedDescription)"
        }
    }

    /// Restore purchases: asks the App Store for this Apple Account's
    /// subscriptions and sends each to the server.
    func restore() async {
        guard !restoring else { return }
        restoring = true
        defer { restoring = false }
        note = nil
        do {
            try await AppStore.sync()
        } catch StoreKitError.userCancelled {
            return
        } catch {
            note = "Couldn't reach the App Store. Try again."
            return
        }
        if await syncEntitlements(quietly: false) == 0 {
            note = "There's no Cetchup subscription on this Apple Account."
        }
    }

    /// Sends the Apple Account's current subscriptions to the server. Quietly
    /// (at sign-in), only one the server's plan doesn't cover yet.
    @discardableResult
    func syncEntitlements(quietly: Bool = true) async -> Int {
        var sent = 0
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  let tier = PlanTier.forProduct(transaction.productID) else { continue }
            if quietly, let status = PlanStore.shared.status, status.plan >= tier,
               let covered = status.expiresAt, let ends = transaction.expirationDate, covered >= ends {
                continue
            }
            sent += 1
            await send(result, quietly: quietly)
        }
        return sent
    }

    /// One transaction to verify-purchase. Finished once the server has it.
    private func send(_ result: VerificationResult<Transaction>, quietly: Bool, buying tier: PlanTier? = nil) async {
        guard case .verified(let transaction) = result else {
            if !quietly { note = "The App Store couldn't confirm that purchase." }
            return
        }
        #if DEBUG && targetEnvironment(simulator)
        StoreKitTesting.keep(result.jwsRepresentation)
        #endif
        // Signed out: StoreKit hands it over again next launch.
        guard Supabase.shared.userId != nil || Previewing.isOn else { return }
        do {
            let answer = try await PlanAPI.verify(jws: result.jwsRepresentation)
            if let plan = answer.plan { PlanStore.shared.apply(plan) }
            await transaction.finish()
            if let tier, answer.result == "applied" || answer.result == "stale" {
                bought = tier
                note = nil
            }
        } catch {
            if !quietly { note = Self.sentence(for: error, xcode: transaction.environment == .xcode) }
        }
    }

    /// The account a purchase belongs to: its appAccountToken.
    private static var account: UUID? {
        #if DEBUG
        if Previewing.isOn { return PreviewData.me }
        #endif
        return Supabase.shared.userId
    }

    /// What to say when the server didn't take a purchase StoreKit did.
    private static func sentence(for error: Error, xcode: Bool) -> String {
        let raw = error.localizedDescription
        if raw.hasPrefix("Offline preview") {
            return xcode
                ? "Bought in Xcode's StoreKit test. Previews don't talk to Cetchup's server, so your plan stays as it is."
                : "Bought. Previews don't talk to Cetchup's server, so your plan stays as it is."
        }
        let lower = raw.lowercased()
        if lower.contains("function") && lower.contains("not found") {
            return "Bought, but Cetchup's server can't take purchases yet. It tries again the next time Cetchup opens."
        }
        if raw.hasPrefix("Request failed") || error is URLError {
            return "Bought, but Cetchup couldn't reach its server. It tries again the next time Cetchup opens."
        }
        return raw
    }
}
