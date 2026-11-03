//
//  SavedPreviewScreen.swift
//  Ketchup
//
//  The saved catch-ups on fixtures, one per `-screen saved…` name: Breck's
//  "Earlier catch-ups" (full, opened on a catch-up, and empty), a source as
//  it was kept, and every chat's list with what the phone keeps (Breck and
//  an Instagram test thread). They read a scratch DeviceStore, never the
//  real one.
//

#if DEBUG
import SwiftUI

struct SavedPreviewScreen: View {
    enum Screen: String, CaseIterable {
        case list = "saved"
        case brief = "saved-brief"
        case empty = "saved-empty"
        case quote = "saved-quote"
        case all = "saved-all"
    }

    static var names: [String] { Screen.allCases.map(\.rawValue) }

    let name: String
    @State private var app = PreviewData.app()
    @State private var store: DeviceStore

    init(name: String) {
        self.name = name
        _store = State(initialValue: Self.store(filled: name != Screen.empty.rawValue))
    }

    var body: some View {
        Group {
            switch Screen(rawValue: name) {
            case .list, .empty:
                breck()
            case .brief:
                breck(opening: Self.catchUpId)
            case .quote:
                breck()
                    .sheet(isPresented: .constant(true)) {
                        SavedQuoteCard(quote: Self.quote(CorePreviewScreen.jumpTarget)!)
                    }
            case .all:
                NavigationStack {
                    SavedCatchUpsView(store: store)
                }
            case nil:
                PreviewIndex(unknown: name)
            }
        }
        .environment(app)
    }

    private func breck(opening: UUID? = nil) -> some View {
        SavedBriefsSheet(place: .chat(PreviewData.breckId), title: PreviewData.breck.name, store: store, opening: opening)
    }

    // MARK: Fixtures

    static let catchUpId = UUID(uuidString: "5A0E0000-0000-4000-8000-000000000001")!

    /// Breck's live catch-up and two answers, and the Instagram test
    /// thread's catch-up, kept at times that read as today and earlier.
    private static func store(filled: Bool) -> DeviceStore {
        let root = URL.temporaryDirectory.appending(path: "saved-preview-\(UUID().uuidString)", directoryHint: .isDirectory)
        let store = DeviceStore(root: root) { PreviewData.me }
        guard filled else { return store }
        let breck = SavedPlace.chat(PreviewData.breckId)
        let name = PreviewData.breck.name
        let cal = Calendar.current
        let earlier = cal.date(bySettingHour: 18, minute: 5, second: 0, of: cal.date(byAdding: .day, value: -3, to: .now)!)!
        let yesterday = cal.date(bySettingHour: 21, minute: 40, second: 0, of: cal.date(byAdding: .day, value: -1, to: .now)!)!
        let today = Date.now.addingTimeInterval(-25 * 60)

        // Oldest first: keep() puts each on top.
        if let notFound = PreviewData.notFound.result {
            store.keep(SavedBrief(id: UUID(uuidString: "5A0E0000-0000-4000-8000-000000000003")!, kind: .ask,
                                  savedAt: earlier, messageCount: 302, question: PreviewData.notFoundQuestion,
                                  answer: notFound, quotes: notFound.refs.compactMap { quote($0) }),
                       in: breck, name: name)
        }
        if let brief = PreviewData.brief.result {
            store.keep(SavedBrief(id: catchUpId, kind: .catchUp, savedAt: yesterday,
                                  messageCount: PreviewData.brief.messageCount ?? 302, catchUp: brief,
                                  quotes: brief.allRefs.compactMap { quote($0) }),
                       in: breck, name: name)
        }
        if let answer = PreviewData.answer.result {
            store.keep(SavedBrief(id: UUID(uuidString: "5A0E0000-0000-4000-8000-000000000002")!, kind: .ask,
                                  savedAt: today, messageCount: 302, question: PreviewData.answerQuestion,
                                  answer: answer, quotes: answer.refs.compactMap { quote($0) }),
                       in: breck, name: name)
        }
        let thread = WebChatPreviewScreen.thread
        if let web = WebChatPreviewScreen.brief.result {
            store.keep(SavedBrief(id: UUID(uuidString: "5A0E0000-0000-4000-8000-000000000004")!, kind: .catchUp,
                                  savedAt: earlier.addingTimeInterval(-3_600), messageCount: thread.messages.count,
                                  title: thread.displayTitle, catchUp: web,
                                  quotes: web.allRefs.compactMap { ref in
                                      thread.message(ref).map { SavedQuote(id: ref, name: $0.isMe ? "You" : $0.sender, text: $0.text) }
                                  }),
                       in: .web(WebChatSource.instagram.id), name: WebChatSource.instagram.name)
        }
        return store
    }

    /// A Breck message as a saved catch-up keeps it.
    private static func quote(_ id: UUID) -> SavedQuote? {
        guard let m = PreviewData.messages.first(where: { $0.id == id }) else { return nil }
        let name = m.sender == PreviewData.me ? "You" : PreviewData.members.first { $0.userId == m.sender }?.name ?? "Someone"
        return SavedQuote(id: id, name: name, text: m.body, at: m.createdAt)
    }
}
#endif
