//
//  CatchUpContent.swift
//  Ketchup
//
//  A catch-up laid out for someone coming back to the chat, in the order
//  they need it: the gist with its times and money marked, their to-dos,
//  the plans as order tickets, who owes what as a diner check, the
//  questions still waiting on a reply, then the rest of the highlights.
//  Empty sections are left out. Sections rise in once, one after another.
//

import SwiftUI

struct CatchUpContent: View {
    let brief: CatchUp
    /// After "Read by Muse Spark": "302 messages", "23 s".
    var byline: [String] = []
    let chatName: String
    /// The reader as the chat names them ("David"). Muse Spark uses it in
    /// owes and questions; here it turns into "You".
    var readerName: String = ""
    let refs: RefContext

    /// `-section` names for previews and the scroll ids of the sections.
    enum Section: String {
        case forYou = "for-you", plans, owes, questions, highlights
    }

    @State private var shown = false

    /// Seconds the brief waits before rising in, so the skim that was
    /// there has faded out first.
    private static let handOver = 0.14

    var body: some View {
        VStack(alignment: .leading, spacing: 40) {
            header
                .riseIn(shown, index: 0, after: Self.handOver)
            if !brief.forYou.isEmpty {
                forYou
                    .id(Section.forYou.rawValue)
                    .riseIn(shown, index: 2, after: Self.handOver)
            }
            if !brief.plans.isEmpty {
                plans
                    .id(Section.plans.rawValue)
                    .riseIn(shown, index: 3, after: Self.handOver)
            }
            if !brief.owes.isEmpty {
                owes
                    .id(Section.owes.rawValue)
                    .riseIn(shown, index: 4, after: Self.handOver)
            }
            if !brief.openQuestions.isEmpty {
                questions
                    .id(Section.questions.rawValue)
                    .riseIn(shown, index: 5, after: Self.handOver)
            }
            if !brief.highlights.isEmpty {
                highlights
                    .id(Section.highlights.rawValue)
                    .riseIn(shown, index: 6, after: Self.handOver)
            }
        }
        .onAppear { shown = true }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            BriefMarks.moneyAndTimes(brief.tldr)
                .font(.serif(.title2, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .markRuns(sweep: true, delay: Self.handOver + 0.35)
                .accessibilityAddTraits(.isHeader)
            MuseByline(verb: "Read by", details: byline)
        }
    }

    private var forYou: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(firstName.map { "For you, \($0)" } ?? "For you", count: brief.forYou.count)
            ForYouList(items: brief.forYou, refs: refs)
        }
    }

    private var plans: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Plans", count: brief.plans.count)
            ForEach(Array(Self.soonestFirst(brief.plans).enumerated()), id: \.offset) { _, plan in
                PlanCard(plan: plan, chatName: chatName, readerName: readerName, refs: refs)
            }
        }
    }

    private var owes: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Who owes what", count: brief.owes.count)
            OwesCheck(owes: brief.owes, readerName: readerName, refs: refs)
        }
    }

    private var questions: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionTitle("Still unanswered", count: brief.openQuestions.count)
            ForEach(Array(questionsForYouFirst.enumerated()), id: \.offset) { _, question in
                QuestionBubble(question: question, readerName: readerName, refs: refs)
            }
        }
    }

    private var highlights: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionTitle("Highlights", count: brief.highlights.count)
            ForEach(Array(brief.highlights.enumerated()), id: \.offset) { i, item in
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text(verbatim: String(format: "%02d", i + 1))
                        .font(.mono(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.ketchupText)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(item.text)
                            .font(.body)
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        RefChips(refs: item.refs, context: refs)
                    }
                }
            }
        }
    }

    // MARK: Order

    private var firstName: String? {
        readerName.split(separator: " ").first.map(String.init)
    }

    /// Soonest first. Plans with no time go last, in Muse Spark's order.
    static func soonestFirst(_ plans: [CatchUp.Plan]) -> [CatchUp.Plan] {
        plans.enumerated().sorted { a, b in
            switch (a.element.start, b.element.start) {
            case let (x?, y?): x != y ? x < y : a.offset < b.offset
            case (.some, nil): true
            case (nil, .some): false
            case (nil, nil): a.offset < b.offset
            }
        }
        .map(\.element)
    }

    /// Questions that name the reader come first.
    private var questionsForYouFirst: [CatchUp.Question] {
        guard let firstName else { return brief.openQuestions }
        let named = brief.openQuestions.filter { $0.question.localizedCaseInsensitiveContains(firstName) }
        let rest = brief.openQuestions.filter { !$0.question.localizedCaseInsensitiveContains(firstName) }
        return named + rest
    }
}

/// An open question as the asker's message: their monogram and name in
/// their chat color, a received bubble, "No reply yet" under it. The
/// reader's name is marked. Tapping it jumps to the question in the chat.
struct QuestionBubble: View {
    let question: CatchUp.Question
    let readerName: String
    let refs: RefContext

    @ScaledMetric(relativeTo: .body) private var avatar: CGFloat = 30

    var body: some View {
        Button {
            if let first = question.refs.first { refs.jump(first) }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .bottom, spacing: 10) {
                    if let asker {
                        Monogram(name: asker, size: avatar)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        if let asker {
                            Text(asker)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.personColor(name: asker))
                                .padding(.leading, 8)
                        }
                        bubble
                    }
                    Spacer(minLength: 32)
                }
                Kicker("No reply yet")
                    .padding(.leading, (asker == nil ? 0 : avatar + 10) + 8)
            }
        }
        .buttonStyle(.pressable)
        .disabled(question.refs.isEmpty)
        .accessibilityLabel("\(asker.map { "\($0) asked" } ?? "Asked"): \(question.question). No reply yet.")
        .accessibilityHint("Shows it in the chat")
    }

    private var asker: String? {
        guard let name = question.askedBy?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty
        else { return nil }
        return name
    }

    private var bubble: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 6,
                                           bottomTrailingRadius: 18, topTrailingRadius: 18,
                                           style: .continuous)
        return BriefMarks.name(readerName.split(separator: " ").first.map(String.init) ?? "", in: question.question)
            .font(.body)
            .foregroundStyle(Theme.ink)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .markRuns()
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.card, in: shape)
            .overlay(shape.strokeBorder(Theme.rule, lineWidth: 1))
    }
}
