//
//  AIPreviewScreen.swift
//  Ketchup
//
//  The Muse Spark screens on fixtures, one per `-screen ai-…` name: the
//  finished catch-up (and with to-dos checked off), reading (and reading
//  before the thread's messages are here), a failure, nothing new, and Ask (empty, reading, failed, answered, and "the chat
//  doesn't say"). Sheets are shown full screen. `-section plans` (or
//  for-you, owes, questions, highlights) scrolls the catch-up to a section,
//  `-delay 4` makes it land late, and `-reduceMotion YES` previews any
//  screen as Reduce Motion shows it.
//

#if DEBUG
import SwiftUI

struct AIPreviewScreen: View {
    enum Screen: String, CaseIterable {
        case catchUp = "ai-catchup"
        case checked = "ai-checked"
        case loading = "ai-loading"
        case loadingBlank = "ai-loading-blank"
        case error = "ai-error"
        case empty = "ai-empty"
        case ask = "ai-ask"
        case asking = "ai-ask-loading"
        case askError = "ai-ask-error"
        case answer = "ai-answer"
        case notFound = "ai-notfound"
    }

    static var names: [String] { Screen.allCases.map(\.rawValue) }

    let name: String
    @State private var app = PreviewData.app()
    @State private var model: ChatModel

    /// `-reduceMotion YES`: the screen as Reduce Motion shows it.
    private static let reduceMotion = UserDefaults.standard.bool(forKey: "reduceMotion")

    init(name: String) {
        self.name = name
        _model = State(initialValue: Self.model(for: Screen(rawValue: name)))
    }

    /// `-delay 4`: the catch-up lands after that many seconds, to watch the
    /// skim hand over to the brief.
    private static let delay = Duration.seconds(UserDefaults.standard.double(forKey: "delay"))

    /// The Breck chat, primed so each screen lands in its state.
    private static func model(for screen: Screen?) -> ChatModel {
        switch screen {
        case .catchUp, .checked:
            PreviewData.chatModel(delay: delay)
        case .loading:
            PreviewData.chatModel(catchUp: .loading)
        case .loadingBlank:
            PreviewData.emptyChatModel(holds: false)
        case .error:
            PreviewData.chatModel(catchUp: .failed("Muse Spark is busy right now. Try again in a moment."),
                                  delay: .seconds(0.6))
        case .empty:
            PreviewData.chatModel(catchUp: .done(nothingNew), delay: .zero)
        case .asking:
            PreviewData.chatModel(answer: .loading, asked: "When are we leaving?")
        case .askError:
            PreviewData.chatModel(answer: .failed("Couldn't reach Muse Spark. Try again."),
                                  asked: "When are we leaving?")
        case .answer:
            PreviewData.chatModel(asked: PreviewData.answerQuestion)
        case .notFound:
            PreviewData.chatModel(answer: .done(PreviewData.notFound), asked: PreviewData.notFoundQuestion)
        case .ask, nil:
            PreviewData.chatModel()
        }
    }

    /// What the edge function sends back when nothing is unread.
    private static var nothingNew: BriefResponse<CatchUp> {
        BriefResponse(kind: "catch_up", empty: true, cached: false, result: nil, model: "muse-spark-1.3",
                      messageCount: 0, latencyMs: nil, until: nil, error: nil)
    }

    var body: some View {
        Group {
            switch Screen(rawValue: name) {
            case .catchUp, .loading, .loadingBlank, .error, .empty:
                CatchUpSheet(model: model, refs: refs)
            case .checked:
                CatchUpSheet(model: model, refs: refs)
                    .environment(\.previewDone, [0, 2])
            case .ask, .asking, .askError, .answer, .notFound:
                AskSheet(model: model, refs: refs)
            case nil:
                PreviewIndex(unknown: name)
            }
        }
        .environment(app)
        .transformEnvironment(\._accessibilityReduceMotion) { if Self.reduceMotion { $0 = true } }
    }

    /// Ref chips show who said what; tapping one has no chat to jump to here.
    private var refs: RefContext {
        RefContext(preview: { [model] in model.preview($0) }, jump: { _ in })
    }
}
#endif
