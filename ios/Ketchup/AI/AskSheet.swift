//
//  AskSheet.swift
//  Ketchup
//
//  "Ask the chat": a question in, an answer out with the messages that
//  back it up. Muse Spark says so plainly when the chat doesn't have it.
//

import SwiftUI

struct AskSheet: View {
    let model: ChatModel
    let refs: RefContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var question = ""
    @State private var scrolled = false
    @FocusState private var focused: Bool

    private static let suggestions = [
        "What did we decide?",
        "When and where are we meeting?",
        "Who's bringing what?",
        "Does anyone owe me money?",
        "Did anyone answer my question?",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Ask the chat")
                        .font(.serif(.largeTitle))
                        .foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text("\(Theme.modelName) reads the whole chat and answers with receipts.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSoft)
                }
                NotepadField(text: $question, focused: $focused, canAsk: canAsk, submit: submit)
                if stage == .idle {
                    suggestionChips
                        .transition(.opacity)
                }
                result
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > 1
        } action: { _, isScrolled in
            scrolled = isScrolled
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            SheetBar(title: model.chat.name, scrolled: scrolled) { dismiss() }
        }
        .background(Theme.cream)
        .presentationBackground(Theme.cream)
        .presentationDragIndicator(.visible)
        .animation(Motion.choose(Motion.settle, reduceMotion: reduceMotion), value: stage)
        .onAppear {
            if question.isEmpty { question = model.lastQuestion }
            if stage == .idle { focused = true }
        }
    }

    private var suggestionChips: some View {
        VStack(alignment: .leading, spacing: 10) {
            Kicker("Or try one")
            FlowLayout(spacing: 8) {
                ForEach(Self.suggestions, id: \.self) { suggestion in
                    Button(suggestion) {
                        question = suggestion
                        submit()
                    }
                    .buttonStyle(.outline(.compact))
                }
            }
        }
    }

    @ViewBuilder
    private var result: some View {
        switch model.answer {
        case .idle:
            EmptyView()
        case .loading:
            SkimmingView(title: "Looking through the chat",
                         usually: "Usually a few seconds",
                         lines: SkimLine.lines(from: model, startingAt: nil),
                         titleFont: .serif(.title3))
                .transition(.opacity)
        case .failed(let message):
            AIErrorCard(message: message, prominent: false) { retry() }
                .transition(.rise(reduceMotion: reduceMotion))
        case .done(let response):
            if let answer = response.result {
                AnswerCard(question: model.lastQuestion, answer: answer,
                           byline: MuseByline.details(response), refs: refs)
                    .transition(.rise(reduceMotion: reduceMotion))
            } else {
                AIErrorCard(message: "\(Theme.modelName) didn't answer that. Try asking another way.",
                            prominent: false) { retry() }
                    .transition(.rise(reduceMotion: reduceMotion))
            }
        }
    }

    // MARK: State

    private enum Stage: Hashable { case idle, reading, failed, answered }

    private var stage: Stage {
        switch model.answer {
        case .idle: .idle
        case .loading: .reading
        case .failed: .failed
        case .done: .answered
        }
    }

    private var canAsk: Bool {
        !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !model.answer.isLoading
    }

    private func submit() {
        guard canAsk else { return }
        focused = false
        let q = question
        Task { await model.ask(q) }
    }

    /// The last question again, even if the field has changed since.
    private func retry() {
        let q = model.lastQuestion.isEmpty ? question : model.lastQuestion
        Task { await model.ask(q) }
    }
}

/// The question box: a page of a notepad, ruled to the text, with Ask in
/// ketchup red at its foot. Also asks about a chat read off a website (WebChat/).
struct NotepadField: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    let canAsk: Bool
    let submit: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            TextField("Your question", text: $text,
                      prompt: Text("When are we leaving?").foregroundStyle(Theme.inkFaint),
                      axis: .vertical)
                .font(.serif(.title3, weight: .regular))
                .foregroundStyle(Theme.ink)
                .tint(Theme.ketchupText)
                .lineLimit(2...4)
                .focused(focused)
                .submitLabel(.send)
                .onSubmit(submit)
                .background(alignment: .top) {
                    RuledLines(spacing: Self.lineHeight, baseline: Self.baseline)
                        .stroke(Theme.rule, lineWidth: 1)
                        .accessibilityHidden(true)
                }
            Button("Ask", action: submit)
                .buttonStyle(.ketchup(.compact))
                .disabled(!canAsk)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(focused.wrappedValue ? Theme.inkSoft : Theme.rule, lineWidth: 1)
        }
        .motion(Motion.fade, value: focused.wrappedValue)
    }

    /// The field's font, so the rules land under each line of text.
    private static var font: UIFont {
        let base = UIFont.preferredFont(forTextStyle: .title3)
        return base.fontDescriptor.withDesign(.serif).map { UIFont(descriptor: $0, size: 0) } ?? base
    }

    private static var lineHeight: CGFloat { font.lineHeight }
    /// From the top of a line to just under its letters.
    private static var baseline: CGFloat { font.ascender + 4 }
}

/// Notepad rules: one line under each line of text, as far as the frame goes.
nonisolated private struct RuledLines: Shape {
    var spacing: CGFloat
    var baseline: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard spacing > 4 else { return path }
        var y = rect.minY + baseline
        while y <= rect.maxY + 2 {
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += spacing
        }
        return path
    }
}

/// What Muse Spark said, under the question it answers, with the messages
/// behind it. When the chat doesn't say, the card goes quiet: no paper, a
/// dashed edge, and the closest messages it found. Also used by WebChat/.
struct AnswerCard: View {
    let question: String
    let answer: ChatAnswer
    let byline: [String]
    let refs: RefContext

    var body: some View {
        if answer.found {
            found
        } else {
            notFound
        }
    }

    private var found: some View {
        VStack(alignment: .leading, spacing: 14) {
            Kicker(question)
            BriefMarks.moneyAndTimes(answer.answer)
                .font(.serif(.title3, weight: .regular))
                .foregroundStyle(Theme.ink)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .markRuns(sweep: true, delay: 0.25)
            RefChips(refs: answer.refs, context: refs, limit: 2)
            MuseByline(verb: "Answered by", details: byline)
                .padding(.top, 2)
        }
        .paperCard(padding: 18)
    }

    private var notFound: some View {
        let parts = Self.split(answer.answer)
        return VStack(alignment: .leading, spacing: 14) {
            Kicker(question)
            VStack(alignment: .leading, spacing: 6) {
                Text(parts.headline)
                    .font(.serif(.title2))
                    .foregroundStyle(Theme.ink)
                if let rest = parts.rest {
                    Text(rest)
                        .font(.body)
                        .foregroundStyle(Theme.inkSoft)
                }
                // An answer Muse Spark couldn't back with a message.
                if !parts.saysNotFound && answer.refs.isEmpty {
                    Text("\(Theme.modelName) couldn't point to a message for this.")
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSoft)
                        .padding(.top, 2)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            if !answer.refs.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Kicker("Closest it gets")
                    RefChips(refs: answer.refs, context: refs, limit: 2)
                }
            }
            MuseByline(verb: "Answered by", details: byline)
                .padding(.top, 2)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.inkFaint, style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
        }
    }

    /// "The chat doesn't say. Sam asked twice." splits after "say."; any
    /// other answer after its own first sentence ("The chat doesn't say
    /// whether the house has a hot tub."), so nothing is cut mid-sentence.
    /// `saysNotFound` is false for an answer that only lacked a source.
    static func split(_ answer: String) -> (headline: String, rest: String?, saysNotFound: Bool) {
        let text = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        let opener = "the chat doesn't say"
        let saysNotFound = text.replacingOccurrences(of: "’", with: "'").lowercased().hasPrefix(opener)
        if saysNotFound {
            let after = text.dropFirst(opener.count)
            if after.isEmpty || ".:;!".contains(after.first!) {
                let rest = after.drop { " .:;!".contains($0) }.trimmingCharacters(in: .whitespaces)
                return ("The chat doesn't say.", rest.isEmpty ? nil : rest.prefix(1).uppercased() + rest.dropFirst(), true)
            }
        }
        let parts = Sentences.first(text)
        return (parts.first, parts.rest, saysNotFound)
    }
}
