//
//  EventEditor.swift
//  TLDR
//
//  EKEventEditViewController wrapped for SwiftUI, prefilled from a plan.
//  TL;DR never writes to the calendar itself; the user taps Add.
//

import SwiftUI
import EventKit
import EventKitUI

enum CalendarAccess {
    static let store = EKEventStore()

    /// Asks for write-only calendar access (iOS 17+). True if granted.
    static func requestWriteOnly() async -> Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .writeOnly, .fullAccess: return true
        case .denied, .restricted: return false
        default: return (try? await store.requestWriteOnlyAccessToEvents()) ?? false
        }
    }
}

struct EventEditor: UIViewControllerRepresentable {
    let plan: CatchUp.Plan
    let chatName: String
    let onDone: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = CalendarAccess.store
        let event = EKEvent(eventStore: store)
        event.title = plan.title
        event.location = plan.location

        // No time in the chat → next whole hour, for the user to set.
        let fallback = Calendar.current.nextDate(after: .now, matching: DateComponents(minute: 0),
                                                 matchingPolicy: .nextTime) ?? .now
        let start = plan.start ?? fallback
        event.isAllDay = plan.allDay
        event.startDate = start
        if let end = plan.end, end > start {
            event.endDate = end
        } else {
            event.endDate = plan.allDay ? start : start.addingTimeInterval(3600)
        }

        var notes = "From “\(chatName)” on TL;DR, found by Muse Spark."
        if !plan.who.isEmpty { notes += "\nGoing: \(plan.who.joined(separator: ", "))" }
        if !plan.confirmed { notes += "\nStill a proposal in the chat." }
        event.notes = notes
        if let calendar = store.defaultCalendarForNewEvents { event.calendar = calendar }

        let controller = EKEventEditViewController()
        controller.eventStore = store
        controller.event = event
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let onDone: () -> Void
        init(onDone: @escaping () -> Void) { self.onDone = onDone }

        func eventEditViewController(_ controller: EKEventEditViewController,
                                     didCompleteWith action: EKEventEditViewAction) {
            onDone()
        }
    }
}
