//
//  CatchUpSheet.swift
//  Ketchup
//
//  "Catch me up": Muse Spark reads everything since your read cursor and
//  this sheet lays out what came back. Reopening it shows the same brief
//  unless new messages have arrived since. With nothing new since the last
//  catch-up kept on the phone, it shows that one again, with no call
//  ("Nothing new since 2:14 PM"). Under the brief, "Earlier catch-ups"
//  opens the others the phone keeps (Saved/).
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
    /// This chat's catch-ups and answers kept on the phone, newest first.
    @State private var kept: [SavedBrief]
    /// Over the sheet: Earlier catch-ups, or a kept source the chat hasn't loaded.
    @State private var over: Over?

    init(model: ChatModel, refs: RefContext) {
        self.model = model
        self.refs = refs
        _kept = State(initialValue: DeviceStore.shared.saved(.chat(model.chat.id))?.briefs ?? [])
    }

    #if DEBUG
    /// Offline previews: opens with Earlier catch-ups over it (`-screen brief-history`).
    init(model: ChatModel, refs: RefContext, opensEarlier: Bool) {
        self.init(model: model, refs: refs)
        _over = State(initialValue: opensEarlier ? .earlier : nil)
    }
    #endif

    private enum Over: Identifiable {
        case earlier
        case quote(SavedQuote)

        var id: String {
            switch self {
            case .earlier: "earlier"
            case .quote(let quote): quote.id.uuidString
            }
        }
    }

    /// The Earlier catch-ups row's scroll id (`-section earlier` in previews).
    private static let earlierId = "earlier"

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
            reloadKept()
        }
        // Unstructured on purpose: swiping the sheet away mid-request
        // shouldn't cancel it; the brief is waiting when it reopens.
        .onAppear {
            Task {
                await model.catchUpIfNeeded()
                reloadKept()  // a prefetched brief is kept once it's opened
            }
        }
        .sheet(item: $over, onDismiss: reloadKept) { over in
            switch over {
            case .earlier:
                SavedBriefsSheet(place: .chat(model.chat.id), title: model.chat.name,
                                 livePreview: refs.preview, jump: refs.jump)
            case .quote(let quote):
                SavedQuoteCard(quote: quote)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        // One branch for the kept catch-up, whether catchUpIfNeeded has
        // landed on it yet or not, so it doesn't arrive twice.
        if let last = shownKept {
            keptPage(last)
        } else {
            phaseContent
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch model.catchUp {
        case .idle, .loading:
            SkimmingView(title: readingTitle,
                         subtitle: "\(Theme.modelName) is skimming so you don't have to.",
                         usually: "Usually about 20 seconds",
                         lines: SkimLine.lines(from: model, startingAt: model.firstUnreadId))
                // Gone quickly, before the brief rises into its place.
                .transition(.opacity.animation(Motion.fade))
        case .failed(let message):
            VStack(alignment: .leading, spacing: 28) {
                AIErrorCard(message: message, note: "Nothing was marked as read.") {
                    Task { await model.runCatchUp() }
                }
                earlier(besides: nil)
            }
            .transition(.rise(reduceMotion: reduceMotion))
        case .done(let response):
            if let brief = response.result {
                VStack(alignment: .leading, spacing: 40) {
                    CatchUpContent(brief: brief,
                                   byline: MuseByline.details(response),
                                   chatName: model.chat.name,
                                   readerName: readerName,
                                   refs: refs)
                    earlier(besides: response.briefId)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    CaughtUpCard()
                    earlier(besides: nil)
                }
                .transition(.rise(reduceMotion: reduceMotion))
            }
        }
    }

    /// Nothing new: the last catch-up kept on the phone, as it was, under a
    /// line that says so. Its sources read from the chat when it has them
    /// loaded, and otherwise as they were kept.
    private func keptPage(_ last: SavedBrief) -> some View {
        VStack(alignment: .leading, spacing: 28) {
            NothingNewNote(since: last.savedAt, readSince: model.hasNewMessages(since: last))
            if let brief = last.catchUp {
                CatchUpContent(brief: brief,
                               byline: last.byline,
                               chatName: model.chat.name,
                               readerName: readerName,
                               refs: .kept(last, live: refs.preview, jump: refs.jump, photo: refs.photo,
                                           show: { over = .quote($0) }))
            }
            earlier(besides: last.id)
                .padding(.top, 12)
        }
    }

    /// "Earlier catch-ups", when the phone keeps any besides the one on screen.
    @ViewBuilder
    private func earlier(besides shown: UUID?) -> some View {
        if kept.contains(where: { $0.id != shown }) {
            EarlierCatchUpsRow(kept: kept) { over = .earlier }
                .id(Self.earlierId)
        }
    }

    // MARK: State

    private enum Stage: Hashable { case reading, failed, empty, kept, brief }

    private var stage: Stage {
        switch model.catchUp {
        case .idle, .loading: shownKept == nil ? .reading : .kept
        case .failed: .failed
        case .done(let response): response.result != nil ? .brief : shownKept == nil ? .empty : .kept
        }
    }

    /// The chat's newest kept catch-up, when it's the one to show: nothing
    /// is unread (the server said so, or catchUpIfNeeded is about to find
    /// nothing new since it and show it without a call).
    private var shownKept: SavedBrief? {
        guard let last = kept.first(where: { $0.kind == .catchUp }), last.catchUp != nil else { return nil }
        switch model.catchUp {
        case .done(let response) where response.result == nil:
            return last
        case .idle where model.synced && model.unreadCount == 0 && !model.hasNewMessages(since: last):
            return last
        default:
            return nil
        }
    }

    private func reloadKept() {
        kept = DeviceStore.shared.saved(.chat(model.chat.id))?.briefs ?? []
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
    /// `-section plans` (or for-you, owes, questions, highlights, earlier)
    /// scrolls a preview of the brief to that section.
    private func scrollToPreviewSection(_ proxy: ScrollViewProxy) async {
        guard stage == .brief || stage == .kept, let section = PreviewData.section else { return }
        try? await Task.sleep(for: .milliseconds(450))
        proxy.scrollTo(section, anchor: .top)
    }
    #endif
}
