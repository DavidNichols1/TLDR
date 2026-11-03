//
//  WebChatSheet.swift
//  Ketchup
//
//  EXPERIMENTAL, NOT RELEASED. Catch me up for a thread read off a
//  source's website, laid out with the same Muse Spark pieces as Ketchup's
//  own chats: the skim while it reads, the brief, Ask. A source chip can't
//  jump to the message (it isn't in Ketchup), so it shows the whole message
//  instead. Nothing here is saved.
//

import SwiftUI

/// One catch-up on a thread read off a website, and any questions asked
/// after it. In memory only, for as long as the sheet is open.
@Observable
final class WebCatchUp: Identifiable {
    let id = UUID()
    let thread: WebThread
    let readerName: String
    private(set) var brief: AIPhase<BriefResponse<CatchUp>>
    private(set) var answer: AIPhase<BriefResponse<ChatAnswer>>
    private(set) var lastQuestion = ""
    /// A source somebody tapped, shown whole.
    var quote: Quote?

    struct Quote: Identifiable {
        let id: UUID
        let message: WebMessage
    }

    init(thread: WebThread, readerName: String,
         brief: AIPhase<BriefResponse<CatchUp>> = .idle,
         answer: AIPhase<BriefResponse<ChatAnswer>> = .idle, lastQuestion: String = "") {
        self.thread = thread
        self.readerName = readerName
        self.brief = brief
        self.answer = answer
        self.lastQuestion = lastQuestion
    }

    /// Asks Muse Spark once; the sheet calls it when it opens.
    func start() async {
        guard case .idle = brief else { return }
        await run()
    }

    func run() async {
        brief = .loading
        do {
            brief = .done(try await WebChatAPI.catchUp(thread, readerName: readerName))
        } catch {
            brief = .failed(WebChatError.message(for: error))
        }
    }

    func ask(_ question: String) async {
        let q = String(question.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
        guard !q.isEmpty, !answer.isLoading else { return }
        lastQuestion = q
        answer = .loading
        do {
            answer = .done(try await WebChatAPI.ask(q, about: thread, readerName: readerName))
        } catch {
            answer = .failed(WebChatError.message(for: error))
        }
    }

    /// Chips name the reader "You", like the chat does, and show the whole
    /// message when tapped.
    var refs: RefContext {
        RefContext(preview: { [thread] id in thread.message(id).map { ($0.isMe ? "You" : $0.sender, $0.text) } },
                   jump: { [weak self] id in
                       guard let self, let message = thread.message(id) else { return }
                       quote = Quote(id: id, message: message)
                   },
                   hint: "Shows the whole message")
    }

    /// The thread's own messages, for the skim while Muse Spark reads.
    var skimLines: [SkimLine] {
        thread.messages.map { m in
            let name = m.isMe ? "You" : m.sender
            return SkimLine(name: name, text: m.text.replacingOccurrences(of: "\n", with: " "), color: RefChip.color(for: name))
        }
    }
}

struct WebChatSheet: View {
    let session: WebCatchUp
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrolled = false
    @State private var question = ""
    @FocusState private var focused: Bool

    private var source: WebChatSource { session.thread.source }

    var body: some View {
        @Bindable var session = session
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                content
                if stage == .brief {
                    ask
                        .transition(.rise(reduceMotion: reduceMotion))
                }
                if stage == .brief {
                    footer
                        .transition(.opacity)
                }
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
            SheetBar(title: session.thread.displayTitle, scrolled: scrolled) { dismiss() }
        }
        .background(Theme.cream)
        .presentationBackground(Theme.cream)
        .presentationDragIndicator(.visible)
        .animation(Motion.choose(Motion.settle, reduceMotion: reduceMotion), value: stage)
        .sensoryFeedback(.success, trigger: stage) { old, new in old == .reading && new == .brief }
        .sheet(item: $session.quote) { quote in
            WebQuoteCard(message: quote.message, source: source)
        }
        .task { await session.start() }
    }

    // MARK: Brief

    @ViewBuilder
    private var content: some View {
        switch session.brief {
        case .idle, .loading:
            SkimmingView(title: readingTitle,
                         subtitle: "\(Theme.modelName) is skimming your \(source.name) chat so you don't have to.",
                         usually: "Usually 10 to 25 seconds",
                         lines: session.skimLines)
                .transition(.opacity.animation(Motion.fade))
        case .failed(let message):
            AIErrorCard(message: message, note: "Nothing from the chat was saved.") {
                Task { await session.run() }
            }
            .transition(.rise(reduceMotion: reduceMotion))
        case .done(let response):
            if let brief = response.result {
                CatchUpContent(brief: brief,
                               byline: byline(response),
                               chatName: session.thread.displayTitle,
                               readerName: session.readerName,
                               refs: session.refs)
            } else {
                AIErrorCard(message: "\(Theme.modelName) didn't send a catch-up back. Try again.") {
                    Task { await session.run() }
                }
                .transition(.rise(reduceMotion: reduceMotion))
            }
        }
    }

    /// "Read by Muse Spark · 120 Instagram messages · 18 s".
    private func byline(_ response: BriefResponse<CatchUp>) -> [String] {
        var parts: [String] = []
        if let count = response.messageCount, count > 0 {
            parts.append(count == 1 ? "1 \(source.name) message" : "\(count.formatted()) \(source.name) messages")
        }
        if let ms = response.latencyMs, ms > 0 {
            parts.append("\(max(1, Int((Double(ms) / 1000).rounded()))) s")
        }
        return parts
    }

    private var readingTitle: String {
        let count = session.thread.messages.count
        return count == 1 ? "Reading 1 message" : "Reading \(count.formatted()) messages"
    }

    // MARK: Ask

    private var ask: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle("Ask this chat")
            NotepadField(text: $question, focused: $focused, canAsk: canAsk, submit: submit)
            switch session.answer {
            case .idle:
                EmptyView()
            case .loading:
                SkimmingView(title: "Looking through the chat",
                             usually: "Usually a few seconds",
                             lines: session.skimLines,
                             titleFont: .serif(.title3))
                    .transition(.opacity)
            case .failed(let message):
                AIErrorCard(message: message, prominent: false) {
                    Task { await session.ask(session.lastQuestion) }
                }
                .transition(.rise(reduceMotion: reduceMotion))
            case .done(let response):
                if let answer = response.result {
                    AnswerCard(question: session.lastQuestion, answer: answer,
                               byline: MuseByline.details(response), refs: session.refs)
                        .transition(.rise(reduceMotion: reduceMotion))
                }
            }
        }
        .motion(Motion.settle, value: answerStage)
    }

    private var canAsk: Bool {
        !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !session.answer.isLoading
    }

    private func submit() {
        guard canAsk else { return }
        focused = false
        let q = question
        Task { await session.ask(q) }
    }

    // MARK: Footer

    /// What this covered, and that it's an experiment, said once and quietly.
    private var footer: some View {
        let thread = session.thread
        let covers = thread.reachedStart && !thread.truncated
            ? "Covers the whole chat."
            : "Covers the last \(thread.messages.count.formatted()) messages."
        return Text("\(covers) Read from the \(source.name) chat open on this phone, and nothing from it was saved. Experimental, not in the released app.")
            .font(.footnote)
            .foregroundStyle(Theme.inkSoft)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: State

    private enum Stage: Hashable { case reading, failed, brief }

    private var stage: Stage {
        switch session.brief {
        case .idle, .loading: .reading
        case .failed: .failed
        case .done(let response): response.result == nil ? .failed : .brief
        }
    }

    private enum AnswerStage: Hashable { case idle, reading, failed, answered }

    private var answerStage: AnswerStage {
        switch session.answer {
        case .idle: .idle
        case .loading: .reading
        case .failed: .failed
        case .done: .answered
        }
    }
}

/// A source, whole: who said it, in their chat color, what they said, and
/// about when. It's all from the page; nothing was kept.
struct WebQuoteCard: View {
    let message: WebMessage
    let source: WebChatSource

    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .headline) private var avatar: CGFloat = 32

    private var name: String { message.isMe ? "You" : message.sender }

    private var text: some View {
        Text(verbatim: message.text)
            .font(.body)
            .foregroundStyle(Theme.ink)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Monogram(name: name, color: RefChip.color(for: name), size: avatar)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: name)
                        .font(.headline)
                        .foregroundStyle(RefChip.color(for: name))
                    if let when {
                        Text(verbatim: when)
                            .font(.mono(.caption))
                            .foregroundStyle(Theme.inkSoft)
                    }
                }
                Spacer(minLength: 8)
                Button("Done") { dismiss() }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .buttonStyle(.pressable)
            }
            // A short message just sits there; a long one scrolls.
            ViewThatFits(in: .vertical) {
                text
                ScrollView { text }
            }
            Text("From your \(source.name) chat. Not saved.")
                .font(.footnote)
                .foregroundStyle(Theme.inkSoft)
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.cream)
        .presentationDetents([.fraction(0.35), .medium])
        .presentationBackground(Theme.cream)
        .presentationDragIndicator(.visible)
    }

    /// "About Sat 9:15 PM": the page only prints times at breaks in the chat.
    private var when: String? {
        guard let at = message.at, let date = JSON.date(from: at) else { return nil }
        return "About \(date.formatted(.dateTime.weekday(.abbreviated).hour().minute()))"
    }
}
