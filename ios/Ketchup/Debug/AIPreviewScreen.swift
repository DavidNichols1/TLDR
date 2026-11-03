//
//  AIPreviewScreen.swift
//  Ketchup
//
//  The Muse Spark screens on fixtures, one per `-screen ai-…` name: the
//  finished catch-up, loading, a failure, Ask (empty, answered, and "the
//  chat doesn't say"). Sheets are shown full screen.
//

#if DEBUG
import SwiftUI

struct AIPreviewScreen: View {
    enum Screen: String, CaseIterable {
        case catchUp = "ai-catchup"
        case loading = "ai-loading"
        case error = "ai-error"
        case ask = "ai-ask"
        case answer = "ai-answer"
        case notFound = "ai-notfound"
    }

    static var names: [String] { Screen.allCases.map(\.rawValue) }

    let name: String
    @State private var app = PreviewData.app()
    @State private var model: ChatModel

    init(name: String) {
        self.name = name
        _model = State(initialValue: Self.model(for: Screen(rawValue: name)))
    }

    /// The Breck chat, primed so each screen lands in its state.
    private static func model(for screen: Screen?) -> ChatModel {
        switch screen {
        case .catchUp:
            PreviewData.chatModel(delay: .zero)
        case .loading:
            PreviewData.chatModel(catchUp: .loading)
        case .error:
            PreviewData.chatModel(catchUp: .failed("Muse Spark is busy right now. Try again in a moment."),
                                  delay: .seconds(0.6))
        case .answer:
            PreviewData.chatModel(asked: PreviewData.answerQuestion)
        case .notFound:
            PreviewData.chatModel(answer: .done(PreviewData.notFound), asked: PreviewData.notFoundQuestion)
        case .ask, nil:
            PreviewData.chatModel()
        }
    }

    var body: some View {
        Group {
            switch Screen(rawValue: name) {
            case .catchUp, .loading, .error:
                CatchUpSheet(model: model, refs: refs)
            case .ask, .answer, .notFound:
                AskSheet(model: model, refs: refs)
            case nil:
                PreviewIndex(unknown: name)
            }
        }
        .environment(app)
    }

    /// Ref chips show who said what; tapping one has no chat to jump to here.
    private var refs: RefContext {
        RefContext(preview: { [model] in model.preview($0) }, jump: { _ in })
    }
}
#endif
