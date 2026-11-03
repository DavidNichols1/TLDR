//
//  CatchUpSheet.swift
//  Ketchup
//
//  "Catch me up": Muse Spark reads everything since your read cursor and
//  this sheet lays out what came back. Reopening it shows the same brief
//  unless new messages have arrived since.
//

import SwiftUI

struct CatchUpSheet: View {
    let model: ChatModel
    let refs: RefContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppModel.self) private var app: AppModel?
    @State private var scrolled = false
    /// Briefs that landed while the sheet was open, for the success haptic.
    @State private var arrivals = 0

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                ZStack(alignment: .top) {
                    content
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 40)
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > 1
            } action: { _, isScrolled in
                scrolled = isScrolled
            }
            #if DEBUG
            .task(id: stage) { await scrollToPreviewSection(proxy) }
            #endif
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            SheetBar(title: model.chat.name, scrolled: scrolled) { dismiss() }
        }
        .background(Theme.cream)
        .presentationBackground(Theme.cream)
        .presentationDragIndicator(.visible)
        .animation(Motion.choose(Motion.settle, reduceMotion: reduceMotion), value: stage)
        .sensoryFeedback(.success, trigger: arrivals)
        .onChange(of: stage) { old, new in
            if old == .reading && new == .brief { arrivals += 1 }
        }
        // Unstructured on purpose: swiping the sheet away mid-request
        // shouldn't cancel it; the brief is waiting when it reopens.
        .onAppear { Task { await model.catchUpIfNeeded() } }
    }

    @ViewBuilder
    private var content: some View {
        switch model.catchUp {
        case .idle, .loading:
            SkimmingView(title: readingTitle,
                         subtitle: "\(Theme.modelName) is skimming so you don't have to.",
                         usually: "Usually about 20 seconds",
                         lines: SkimLine.lines(from: model, startingAt: model.firstUnreadId))
                // Gone quickly, before the brief rises into its place.
                .transition(.opacity.animation(Motion.fade))
        case .failed(let message):
            AIErrorCard(message: message, note: "Nothing was marked as read.") {
                Task { await model.runCatchUp() }
            }
            .transition(.rise(reduceMotion: reduceMotion))
        case .done(let response):
            if let brief = response.result {
                CatchUpContent(brief: brief,
                               byline: MuseByline.details(response),
                               chatName: model.chat.name,
                               readerName: readerName,
                               refs: refs)
            } else {
                CaughtUpCard()
                    .transition(.rise(reduceMotion: reduceMotion))
            }
        }
    }

    // MARK: State

    private enum Stage: Hashable { case reading, failed, empty, brief }

    private var stage: Stage {
        switch model.catchUp {
        case .idle, .loading: .reading
        case .failed: .failed
        case .done(let response): response.result == nil ? .empty : .brief
        }
    }

    /// "Reading 302 messages".
    private var readingTitle: String {
        switch model.unreadAtOpen {
        case 0: "Reading the chat"
        case 1: "Reading 1 message"
        case let count: "Reading \(count.formatted()) messages"
        }
    }

    /// The reader as the chat names them ("David"), which is how Muse Spark
    /// writes them in owes and questions. Members without a profile come
    /// through as "Someone", which isn't a name to greet.
    private var readerName: String {
        [app?.me?.displayName, model.names[model.myId]]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && $0 != "Someone" } ?? ""
    }

    #if DEBUG
    /// `-section plans` (or for-you, owes, questions, highlights) scrolls a
    /// preview of the brief to that section.
    private func scrollToPreviewSection(_ proxy: ScrollViewProxy) async {
        guard stage == .brief, let section = PreviewData.section else { return }
        try? await Task.sleep(for: .milliseconds(450))
        proxy.scrollTo(section, anchor: .top)
    }
    #endif
}
