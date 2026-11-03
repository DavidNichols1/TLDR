//
//  PlanGate.swift
//  Ketchup
//
//  Where plans step into a Muse Spark request, through two marked hooks in
//  Net/Supabase.swift:
//  - Before catch-up or catch-up-text goes out: until you've said yes, the
//    one-time consent sheet (AIConsentSheet). The server refuses without it
//    anyway (403), so this is the friendly way in, not the lock.
//  - When one comes back 402 (today's allowance is used up): the paywall,
//    over the sheet you're reading, with what happened.
//  Both step in only for a request you're watching, one asked from a sheet
//  (Catch me up, Ask, a web chat's catch-up). One that started on its own
//  (the prefetch when a chat opens) waits for your tap instead, so a sheet
//  never appears out of nowhere. On Free the prefetch always waits for the
//  tap, so opening chats doesn't spend the day's allowance.
//
//  The sheets are presented with UIKit from whatever is on top, so no
//  screen has to know about them.
//

import SwiftUI
import UIKit

enum PlanGate {
    /// The edge functions that send messages to Muse Spark.
    static let museFunctions: Set<String> = ["catch-up", "catch-up-text"]

    /// Before a Muse Spark request. Throws when it shouldn't go yet.
    static func beforeMuse(_ function: String) async throws {
        guard museFunctions.contains(function), !Previewing.isOn else { return }
        let store = PlanStore.shared
        await store.loadIfNeeded()
        guard store.available else { return }
        let top = PlanSheets.watching()
        // A catch-up that started on its own (the prefetch when a chat opens)
        // spends the allowance only on Plus and Pro. On Free it waits for
        // your tap, so opening chats doesn't use up the day's 150.
        if top == nil, store.plan == .free { throw ConsentError.waiting }
        guard !store.consented else { return }
        guard let top else { throw ConsentError.waiting }
        // Two requests at once (Catch me up and Ask) share one question.
        let ask = question ?? Task { await askAndSave(over: top) }
        question = ask
        let outcome = await ask.value
        question = nil
        if let refusal = outcome { throw refusal }
    }

    /// The question on screen now, if there is one.
    private static var question: Task<ConsentError?, Never>?

    /// Nil once you've said yes and the server has it.
    private static func askAndSave(over top: UIViewController) async -> ConsentError? {
        guard await PlanSheets.askConsent(over: top) else { return .declined }
        do {
            try await PlanAPI.giveConsent()
        } catch {
            return .notSaved
        }
        PlanStore.shared.consentGiven()
        return nil
    }

    /// A 402 or 403 from the server, before it becomes the error message.
    static func serverRefused(status: Int, data: Data) {
        guard let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let kind = body["kind"] as? String else { return }
        switch (status, kind) {
        case (402, "plan_limit"):
            guard let hit = try? JSON.decoder.decode(PlanLimitHit.self, from: data) else { return }
            PlanStore.shared.limitReached(hit)
            if let top = PlanSheets.watching() { PlanSheets.showPaywall(for: hit, over: top) }
        case (403, "consent_required"):
            PlanStore.shared.consentMissing()
        default:
            break
        }
    }
}

/// Why a Muse Spark request didn't go. The sheets show these as the error.
enum ConsentError: LocalizedError {
    /// It started on its own: before you'd said yes, or on Free. Your tap runs it.
    case waiting
    case declined
    case notSaved

    var errorDescription: String? {
        switch self {
        case .waiting: "Tap Try again to start your catch-up."
        case .declined: "Nothing was sent to Muse Spark."
        case .notSaved: "Couldn't save your OK. Check your connection and try again."
        }
    }
}

/// Plans' two sheets, presented from UIKit over whatever is on top.
enum PlanSheets {
    /// The top view controller when a sheet is up: a request someone asked
    /// for. Nil when nothing is presented (a request that started itself).
    static func watching() -> UIViewController? {
        guard let root = keyWindow?.rootViewController else { return nil }
        var top = root
        while let next = top.presentedViewController, !next.isBeingDismissed { top = next }
        return top === root ? nil : top
    }

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }

    private static var paywallShowing = false

    static func showPaywall(for hit: PlanLimitHit, over top: UIViewController) {
        guard !paywallShowing else { return }
        paywallShowing = true
        Task {
            await settle(top)
            present(over: top, lockedOpen: false, onGone: { paywallShowing = false }) { close in
                PaywallSheet(hit: hit, close: close)
            }
        }
    }

    /// The consent sheet; true once you've said yes.
    static func askConsent(over top: UIViewController) async -> Bool {
        await settle(top)
        return await withCheckedContinuation { continuation in
            var answered = false
            let answer = { (yes: Bool) in
                guard !answered else { return }
                answered = true
                continuation.resume(returning: yes)
            }
            present(over: top, lockedOpen: false, onGone: { answer(false) }) { close in
                AIConsentSheet { yes in
                    answer(yes)
                    close()
                }
            }
        }
    }

    /// Waits out a sheet that's still sliding in (a 402 can beat it).
    private static func settle(_ controller: UIViewController) async {
        for _ in 0..<40 where controller.isBeingPresented || controller.transitionCoordinator != nil {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    private static func present<Content: View>(over top: UIViewController, lockedOpen: Bool,
                                               onGone: @escaping () -> Void,
                                               content: (_ close: @escaping () -> Void) -> Content) {
        let host = PlanSheetController(rootView: AnyView(EmptyView()))
        host.onGone = onGone
        let close: () -> Void = { [weak host] in
            host?.dismiss(animated: true) { host?.gone() }
        }
        host.rootView = AnyView(content(close).tint(Theme.ketchupText))
        host.modalPresentationStyle = .pageSheet
        host.isModalInPresentation = lockedOpen
        host.view.backgroundColor = UIColor(Theme.cream)
        host.presentationController?.delegate = host
        top.present(host, animated: true)
    }
}

/// A sheet that says when it's gone, however it went (a button or a swipe).
private final class PlanSheetController: UIHostingController<AnyView>, UIAdaptivePresentationControllerDelegate {
    var onGone: () -> Void = {}
    private var reported = false

    func gone() {
        guard !reported else { return }
        reported = true
        onGone()
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        gone()
    }
}
