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
//  The `brief-` names are the catch-up sheet with Breck's last 3 catch-ups
//  kept: `brief-history` opens Earlier catch-ups over a new catch-up, and
//  `brief-nothing-new` taps Catch me up with nothing new since the last one
//  (that one again, no call; `-section earlier` scrolls to the row under
//  it). `brief-chat` is the same chat as a thread, all read, with "Your
//  catch-up" in its bar, to tap through: the sheet, Earlier catch-ups, and
//  a source back into the thread. Those run the real ChatModel and
//  CatchUpSheet, so they read DeviceStore.shared: the preview's own scratch
//  folder, as a made-up user.
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
        case history = "brief-history"
        case nothingNew = "brief-nothing-new"
        case chat = "brief-chat"
    }

    static var names: [String] { Screen.allCases.map(\.rawValue) }

    let name: String
    @State private var app = PreviewData.app()
    @State private var store: DeviceStore
    /// The Breck chat for the `brief-` screens.
    @State private var model: ChatModel?

    init(name: String) {
        self.name = name
        let screen = Screen(rawValue: name)
        _store = State(initialValue: Self.store(filled: [.list, .brief, .quote, .all].contains(screen)))
        switch screen {
        case .history: _model = State(initialValue: Self.briefModel(nothingNew: false))
        case .nothingNew, .chat: _model = State(initialValue: Self.briefModel(nothingNew: true))
        default: break
        }
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
            case .history, .nothingNew:
                if let model {
                    BriefPreview(model: model, opensEarlier: name == Screen.history.rawValue)
                }
            case .chat:
                if let model {
                    NavigationStack {
                        ChatView(model: model)
                    }
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

    // MARK: The brief- screens

    /// Whose folder DeviceStore.shared uses for the `brief-` screens: made
    /// up, so it never meets `chat-kept`'s copy.
    private static let briefUser = UUID(uuidString: "5A0E0000-0000-4000-8000-0000000000AA")!

    /// Breck, and the catch-ups the phone keeps for it. `nothingNew`: you've
    /// read it all and the newest kept catch-up read through the last
    /// message, so Catch me up has nothing to ask for. Its Muse Spark call
    /// is set to fail, so a call that shouldn't happen shows. Otherwise all
    /// 302 are unread and the catch-up lands at once.
    private static func briefModel(nothingNew: Bool) -> ChatModel {
        let last = PreviewData.messages.last?.createdAt ?? .now
        let model: ChatModel
        if nothingNew {
            var chat = PreviewData.breck
            chat.lastReadAt = last
            chat.unreadCount = 0
            model = ChatModel.preview(chat: chat, myId: PreviewData.me, members: PreviewData.members,
                                      messages: PreviewData.messages,
                                      catchUp: .failed("This preview asked Muse Spark for a catch-up, but nothing is new."),
                                      answer: .done(PreviewData.answer), delay: .zero)
        } else {
            model = PreviewData.chatModel(delay: .zero)
        }
        PreviewData.storeUser = briefUser
        keepBreckHistory(newestAt: Date.now.addingTimeInterval(nothingNew ? -25 * 60 : -60), readThrough: last)
        return model
    }

    /// Four catch-ups and an answer, oldest first, into DeviceStore.shared:
    /// the oldest falls off, so Breck keeps its last 3. The newest is
    /// Muse Spark's real catch-up of all 302 messages; the two before it
    /// are written by hand for the preview, citing real fixture messages.
    private static func keepBreckHistory(newestAt: Date, readThrough: Date) {
        let store = DeviceStore.shared
        let breck = SavedPlace.chat(PreviewData.breckId)
        let name = PreviewData.breck.name
        store.forgetAll(in: breck)
        let cal = Calendar.current
        func day(_ ago: Int, _ hour: Int, _ minute: Int) -> Date {
            cal.date(bySettingHour: hour, minute: minute, second: 0, of: cal.date(byAdding: .day, value: -ago, to: .now)!)!
        }
        func catchUp(_ id: Int, _ at: Date, _ count: Int, until: Date, _ brief: CatchUp) -> SavedBrief {
            SavedBrief(id: UUID(uuidString: String(format: "5A0E0000-0000-4000-8000-0000000001%02d", id))!,
                       kind: .catchUp, savedAt: at, messageCount: count, until: until, catchUp: brief,
                       quotes: brief.allRefs.compactMap { quote($0) })
        }
        store.keep(catchUp(1, day(4, 19, 20), 12, until: Ref.at("2cd28468-257f-5bf5-a1b7-e69a5f0df8c9"), Ref.rentals), in: breck, name: name)
        store.keep(catchUp(2, day(3, 18, 5), 58, until: Ref.at("25b0acf3-783c-546b-9633-de2258fe9cf0"), Ref.final), in: breck, name: name)
        store.keep(catchUp(3, day(1, 21, 40), 46, until: Ref.at("4e4df5db-ff66-5476-bf1d-fb80f0fc6fc7"), Ref.powderDay), in: breck, name: name)
        if let answer = PreviewData.answer.result {
            store.keep(SavedBrief(id: UUID(uuidString: "5A0E0000-0000-4000-8000-000000000150")!, kind: .ask,
                                  savedAt: day(1, 22, 5), messageCount: 302, question: PreviewData.answerQuestion,
                                  answer: answer, quotes: answer.refs.compactMap { quote($0) }),
                       in: breck, name: name)
        }
        if let brief = PreviewData.brief.result {
            store.keep(catchUp(4, newestAt, PreviewData.brief.messageCount ?? 302, until: readThrough, brief), in: breck, name: name)
        }
    }

    /// The two earlier catch-ups, written by hand (not Muse Spark's words),
    /// and the one that falls off.
    private enum Ref {
        static func id(_ raw: String) -> UUID { UUID(uuidString: raw)! }

        static func at(_ raw: String) -> Date {
            PreviewData.messages.first { $0.id == id(raw) }?.createdAt ?? .now
        }

        static let rentals = CatchUp(
            tldr: "Theo wants to know if you still need rentals.",
            highlights: [], plans: [], openQuestions: [], owes: [],
            forYou: [.init(text: "Tell Theo if you still need rentals", refs: [id("2cd28468-257f-5bf5-a1b7-e69a5f0df8c9")])])

        static let final = CatchUp(
            tldr: "Maya made it final: you leave Saturday at 6am from her place, be there at 5:45. Hearthstone moved to Saturday 7:30 and needs a headcount by Thursday noon.",
            highlights: [
                .init(text: "The Friday night at the Airbnb is off for the storm, with $300 back: $540 total, $90 each",
                      refs: [id("8965b458-f950-52ee-8aed-2779f96d705a"), id("6fe6a3cc-7a99-5aa3-a3dd-be8a6a18adb5")]),
            ],
            plans: [], openQuestions: [],
            owes: [.init(who: PreviewData.myName, owesWhom: "Maya", what: "$90 for the Airbnb",
                         refs: [id("76456d57-027d-51bc-8f8a-bea427a7135e")])],
            forYou: [
                .init(text: "Confirm Hearthstone with Priya before Thursday noon",
                      refs: [id("474ac5d1-87b4-5349-b6f3-2d933e4cc91a"), id("a477da8f-a027-5c63-b862-e128235e1748")]),
                .init(text: "Send Theo your height, weight and boot size by Wednesday night if you need rentals",
                      refs: [id("25b0acf3-783c-546b-9633-de2258fe9cf0")]),
            ])

        static let powderDay = CatchUp(
            tldr: "Saturday is a powder day: the storm clears by 3am, and Jordan drives you and Sam for $20 each in gas. Root Down is Thursday 7:30, and Maya can make it five if you say so by tomorrow.",
            highlights: [
                .init(text: "Storm now Friday 1pm to Saturday 3am, roads plowed by morning",
                      refs: [id("3cf99fc9-39ca-544b-b52d-77925ea5330e"), id("bcda05cc-ca75-5537-9ee7-b666b7abd3e5")]),
                .init(text: "Sunday is A-Basin: cars packed by 8, ski 8:30 to 1, leave by 2",
                      refs: [id("9c611e7a-dc5b-54d5-98a3-faabc6a4fe3d"), id("4e4df5db-ff66-5476-bf1d-fb80f0fc6fc7")]),
            ],
            plans: [], openQuestions: [],
            owes: [.init(who: PreviewData.myName, owesWhom: "Jordan", what: "$20 for gas",
                         refs: [id("6d19d2ee-c349-5543-8089-6c46aff56ed3"), id("32786fcc-2ab9-5ada-8beb-f784689649a7")])],
            forYou: [
                .init(text: "Tell Maya by tomorrow if you want in on Root Down Thursday",
                      refs: [id("d7f09fd4-202c-5a18-9c30-16352f6b1a8c")]),
                .init(text: "You're on speaker and Catan duty", refs: [id("86e6fcfe-7f21-57bc-8009-8f5ac05ebaf9")]),
            ])
    }
}

/// The catch-up sheet, full screen as the other Muse Spark previews show it,
/// once the chat has opened (so its unread count is the server's word, the
/// way Catch me up finds it in the app).
private struct BriefPreview: View {
    let model: ChatModel
    let opensEarlier: Bool
    @State private var opened = false

    var body: some View {
        ZStack {
            Theme.cream.ignoresSafeArea()
            if opened {
                CatchUpSheet(model: model, refs: RefContext(preview: { [model] in model.preview($0) }, jump: { _ in }),
                             opensEarlier: opensEarlier)
            }
        }
        .task {
            await model.open()
            opened = true
        }
    }
}
#endif
