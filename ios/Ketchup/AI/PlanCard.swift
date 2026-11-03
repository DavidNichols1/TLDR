//
//  PlanCard.swift
//  Ketchup
//
//  A plan Muse Spark found, as a diner order ticket: what, where, who and
//  the sources left of the tear line; when, and a CONFIRMED or MAYBE stamp,
//  on the stub. "Add to calendar" opens the system event editor, prefilled;
//  the user reviews it and saves it themselves.
//

import SwiftUI
import EventKit

struct PlanCard: View {
    let plan: CatchUp.Plan
    let chatName: String
    /// The reader as the chat names them, to put "You" first in who's going.
    var readerName: String = ""
    let refs: RefContext

    @State private var editing = false

    var body: some View {
        Ticket(notchAt: 0.66) {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(plan.title)
                        .font(.serif(.title3))
                        .foregroundStyle(Theme.ink)
                    if let place {
                        Text(place)
                            .font(.subheadline)
                            .foregroundStyle(Theme.inkSoft)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                if !plan.who.isEmpty {
                    Going(names: plan.who, readerName: readerName)
                }
                RefChips(refs: plan.refs, context: refs)
                addButton
            }
        } stub: {
            VStack(spacing: 14) {
                when
                if plan.confirmed {
                    Stamp("Confirmed")
                } else {
                    Stamp("Maybe", color: Theme.inkSoft, tilt: 3, dashed: true)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $editing) {
            EventEditor(plan: plan, chatName: chatName) { editing = false }
                .ignoresSafeArea()
        }
    }

    // MARK: The stub

    /// "SAT / NOV 7 / 6:00 AM", "ALL DAY" or "TIME TBD".
    private var when: some View {
        VStack(spacing: 2) {
            if let start = plan.start {
                Text(start.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                    .font(.mono(.subheadline, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text(start.formatted(.dateTime.month(.abbreviated).day()).uppercased())
                    .font(.mono(.caption))
                    .foregroundStyle(Theme.inkSoft)
                Text(timeText(start))
                    .font(.mono(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .padding(.top, 4)
                if let until = untilText(start) {
                    Text(until)
                        .font(.mono(.caption2))
                        .foregroundStyle(Theme.inkSoft)
                }
            } else {
                Text("TIME TBD")
                    .font(.mono(.caption, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenWhen)
    }

    private var addButton: some View {
        Button {
            Task {
                // Write-only access is all adding an event needs. The editor
                // runs out of process and works even if it's declined, so
                // open it either way.
                _ = await CalendarAccess.requestWriteOnly()
                editing = true
            }
        } label: {
            Label("Add to calendar", systemImage: "calendar.badge.plus")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .padding(.vertical, 6)
                .contentShape(.rect)
        }
        .buttonStyle(.pressable)
    }

    /// Where, unless the title already says ("Dinner at Hearthstone").
    private var place: String? {
        guard let location = plan.location?.trimmingCharacters(in: .whitespacesAndNewlines),
              !location.isEmpty, !plan.title.localizedCaseInsensitiveContains(location)
        else { return nil }
        return location
    }

    /// A bare date ("2026-11-07") means the chat never said what time.
    private var hasTime: Bool {
        plan.startsAt?.contains("T") ?? false
    }

    private func timeText(_ start: Date) -> String {
        if plan.allDay { return "ALL DAY" }
        guard hasTime else { return "TIME TBD" }
        return start.formatted(date: .omitted, time: .shortened).uppercased()
    }

    /// "TO 1:00 PM" when the plan has an end time.
    private func untilText(_ start: Date) -> String? {
        guard !plan.allDay, hasTime, let end = plan.end, end > start else { return nil }
        return "TO " + end.formatted(date: .omitted, time: .shortened).uppercased()
    }

    private var spokenWhen: String {
        guard let start = plan.start else { return "Time to be decided" }
        let day = start.formatted(.dateTime.weekday(.wide).month(.wide).day())
        if plan.allDay { return "\(day), all day" }
        guard hasTime else { return "\(day), time to be decided" }
        return "\(day) at \(start.formatted(date: .omitted, time: .shortened))"
    }
}

/// Who's going: a few monograms in their chat colors and a short count,
/// with the reader first ("You and 5 more").
private struct Going: View {
    let names: [String]
    let readerName: String

    @ScaledMetric(relativeTo: .footnote) private var size: CGFloat = 24

    var body: some View {
        let readerIn = names.contains { Tab.isReader($0, reader: readerName) }
        let others = names.filter { !Tab.isReader($0, reader: readerName) }
        let faces = (readerIn ? [readerName.isEmpty ? "You" : readerName] : []) + others
        HStack(spacing: 8) {
            HStack(spacing: -size * 0.22) {
                ForEach(Array(faces.prefix(4).enumerated()), id: \.offset) { _, name in
                    Monogram(name: name, size: size)
                        .background(Theme.card, in: tile)
                        .overlay(tile.strokeBorder(Theme.card, lineWidth: 1.5))
                }
            }
            Text(summary(readerIn: readerIn, others: others.count))
                .font(.footnote)
                .foregroundStyle(Theme.inkSoft)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Going: " + ((readerIn ? ["you"] : []) + others).formatted(.list(type: .and)))
    }

    private var tile: RoundedRectangle {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
    }

    private func summary(readerIn: Bool, others: Int) -> String {
        if readerIn {
            return others == 0 ? "Just you" : "You and \(others) more"
        }
        return "\(others) going"
    }
}
