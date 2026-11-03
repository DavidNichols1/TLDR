//
//  PlanCard.swift
//  TLDR
//
//  A plan Muse Spark found in the chat, with the system event editor one
//  tap away (prefilled; the user reviews and saves it themselves).
//

import SwiftUI
import EventKit

struct PlanCard: View {
    let plan: CatchUp.Plan
    let chatName: String
    let refs: RefContext

    @State private var editing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(plan.title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                statusBadge
            }

            VStack(alignment: .leading, spacing: 5) {
                detail(symbol: "clock", text: whenText)
                if let location = plan.location {
                    detail(symbol: "mappin.and.ellipse", text: location)
                }
                if !plan.who.isEmpty {
                    detail(symbol: "person.2", text: plan.who.joined(separator: ", "))
                }
            }

            RefChips(refs: plan.refs, context: refs)

            Button {
                Task {
                    // Write-only access is all adding an event needs. The
                    // editor runs out of process and works even if it's
                    // declined, so open it either way.
                    _ = await CalendarAccess.requestWriteOnly()
                    editing = true
                }
            } label: {
                Label("Add to Calendar", systemImage: "calendar.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.aiPillCompact)
            .padding(.top, 2)
        }
        .aiCard()
        .sheet(isPresented: $editing) {
            EventEditor(plan: plan, chatName: chatName) { editing = false }
                .ignoresSafeArea()
        }
    }

    private var statusBadge: some View {
        Text(plan.confirmed ? "Confirmed" : "Proposed")
            .font(.caption2.weight(.bold))
            .textCase(.uppercase)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(plan.confirmed ? .green : .orange)
            .background((plan.confirmed ? Color.green : Color.orange).opacity(0.15), in: Capsule())
    }

    private func detail(symbol: String, text: String) -> some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }

    private var whenText: String {
        guard let start = plan.start else { return "Time not set yet" }
        if plan.allDay {
            return start.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()) + " · all day"
        }
        let day = start.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        let from = start.formatted(date: .omitted, time: .shortened)
        if let end = plan.end, end > start {
            return "\(day), \(from) – \(end.formatted(date: .omitted, time: .shortened))"
        }
        return "\(day), \(from)"
    }
}
