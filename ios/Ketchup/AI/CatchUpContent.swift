//
//  CatchUpContent.swift
//  Ketchup
//
//  The sections of a catch-up, in the order a returning reader needs them:
//  the gist, anything aimed at them, plans, open questions, who owes what,
//  then the rest of the highlights. Empty sections are left out.
//

import SwiftUI

struct CatchUpContent: View {
    let brief: CatchUp
    let chatName: String
    let refs: RefContext

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(brief.tldr)
                .font(.title3.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
                .aiCard(padding: 18)

            if !brief.forYou.isEmpty {
                section("For you", symbol: "person.crop.circle.badge.exclamationmark", count: brief.forYou.count) {
                    ForEach(Array(brief.forYou.enumerated()), id: \.offset) { _, item in
                        ItemRow(text: item.text, refs: item.refs, context: refs)
                    }
                }
            }

            if !brief.plans.isEmpty {
                section("Plans", symbol: "calendar", count: brief.plans.count) {
                    ForEach(Array(brief.plans.enumerated()), id: \.offset) { _, plan in
                        PlanCard(plan: plan, chatName: chatName, refs: refs)
                    }
                }
            }

            if !brief.openQuestions.isEmpty {
                section("Still unanswered", symbol: "questionmark.bubble", count: brief.openQuestions.count) {
                    ForEach(Array(brief.openQuestions.enumerated()), id: \.offset) { _, q in
                        ItemRow(text: q.question,
                                caption: q.askedBy.map { "Asked by \($0)" },
                                refs: q.refs, context: refs)
                    }
                }
            }

            if !brief.owes.isEmpty {
                section("Who owes what", symbol: "arrow.left.arrow.right", count: brief.owes.count) {
                    ForEach(Array(brief.owes.enumerated()), id: \.offset) { _, o in
                        ItemRow(text: o.owesWhom.map { "\(o.who) → \($0): \(o.what)" } ?? "\(o.who): \(o.what)",
                                refs: o.refs, context: refs)
                    }
                }
            }

            if !brief.highlights.isEmpty {
                section("Highlights", symbol: "star", count: brief.highlights.count) {
                    ForEach(Array(brief.highlights.enumerated()), id: \.offset) { _, item in
                        ItemRow(text: item.text, refs: item.refs, context: refs)
                    }
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, symbol: String, count: Int,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            AISectionHeader(title: title, symbol: symbol, count: count)
            content()
        }
    }
}

/// One bullet: the text, an optional caption, and its source chips.
struct ItemRow: View {
    let text: String
    var caption: String? = nil
    let refs: [UUID]
    let context: RefContext

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle()
                .fill(Theme.aiDiagonal)
                .frame(width: 6, height: 6)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            VStack(alignment: .leading, spacing: 6) {
                Text(text)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                RefChips(refs: refs, context: context)
            }
        }
        .padding(.leading, 6)
    }
}
