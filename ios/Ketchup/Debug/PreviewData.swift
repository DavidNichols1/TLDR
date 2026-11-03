//
//  PreviewData.swift
//  Ketchup
//
//  Offline preview mode, DEBUG builds only. Launch with `-screen <name>`
//  to open one screen on fixture data: no sign-in, no network, no Muse
//  Spark calls. The fixtures are real: the seeded "Breck Weekend 🎿" chat
//  and what Muse Spark actually said about it (Debug/Fixtures/).
//
//    xcrun simctl launch <udid> com.vibetemp.ketchup -screen inbox
//
//  PreviewRouter.swift lists the screens; docs/DESIGN.md has the recipe.
//

#if DEBUG
import SwiftUI

enum PreviewData {

    // MARK: Launch arguments

    /// The `-screen` launch argument (UserDefaults reads `-key value` pairs).
    static let screen: String? = UserDefaults.standard.string(forKey: "screen")
    static var isActive: Bool { screen != nil }
    /// `-section <id>` scrolls a long screen (the design gallery) to a part.
    static let section: String? = UserDefaults.standard.string(forKey: "section")
    /// Whose copy DeviceStore keeps in a preview (in a scratch folder): nobody,
    /// except while `keptChatModel()` sets the Breck chat up, and a made-up
    /// user of their own on the `brief-` screens (SavedPreviewScreen.swift).
    static var storeUser: UUID?

    // MARK: People

    /// The reader. They've been away, so all of Breck is unread.
    static let me = UUID(uuidString: "D0000000-0000-4000-8000-000000000001")!
    static let myName = "David"
    static let maya = UUID(uuidString: "D0000000-0000-4000-8000-000000000002")!
    static let jordan = UUID(uuidString: "D0000000-0000-4000-8000-000000000003")!
    static let priya = UUID(uuidString: "D0000000-0000-4000-8000-000000000004")!
    static let sam = UUID(uuidString: "D0000000-0000-4000-8000-000000000005")!
    static let theo = UUID(uuidString: "D0000000-0000-4000-8000-000000000006")!

    private static let breckCast: [(id: UUID, name: String)] = [
        (me, myName), (maya, "Maya"), (jordan, "Jordan"), (priya, "Priya"), (sam, "Sam"), (theo, "Theo"),
    ]

    static let members: [Member] = breckCast.map { member($0.id, $0.name, joined: breckCreated) }

    // MARK: Breck Weekend

    static let breckId = UUID(uuidString: "B0000000-0000-4000-8000-00000000B4EC")!
    /// Before the first message, which is where the reader's cursor sits.
    private static let breckCreated = JSON.date(from: "2026-10-28T18:00:00Z")!

    /// The 41 messages Muse Spark cited (Fixtures/messages.json; their ids are
    /// the brief's refs), then the chat's last three lines from the seed so
    /// the thread ends where the inbox row says.
    static let messages: [Message] = {
        let cited = load([FixtureMessage].self, "messages").map { m in
            Message(id: m.id, chatId: breckId, sender: id(of: m.name), body: m.body, createdAt: m.createdAt)
        }
        let last = cited.last?.createdAt ?? breckCreated
        let goodnights: [(String, String, String, TimeInterval)] = [
            ("E0000000-0000-4000-8000-000000000001", "Sam", "5:45 is a made up time", 40),
            ("E0000000-0000-4000-8000-000000000002", "Priya", "goodnight!! 🌙", 95),
            ("E0000000-0000-4000-8000-000000000003", "Maya", "goodnight losers 💙", 160),
        ]
        return cited + goodnights.map { uuid, name, body, after in
            Message(id: UUID(uuidString: uuid)!, chatId: breckId, sender: id(of: name), body: body,
                    createdAt: last.addingTimeInterval(after))
        }
    }()

    /// The Breck inbox row: 302 unread, nothing read yet.
    static let breck = ChatSummary(
        id: breckId, name: "Breck Weekend 🎿", inviteCode: "WQGAEA", memberCount: 6,
        createdAt: breckCreated, lastMessageAt: messages.last?.createdAt,
        lastMessagePreview: "goodnight losers 💙", lastMessageSenderName: "Maya",
        lastReadAt: breckCreated, unreadCount: 302)

    // MARK: Muse Spark

    /// The live catch-up of all 302 messages.
    static let brief = load(BriefResponse<CatchUp>.self, "brief")
    /// A live Ask answer, and the question it answered.
    static let answer = load(BriefResponse<ChatAnswer>.self, "ask")
    static let answerQuestion = load(Asked.self, "ask").question
    /// A "the chat doesn't say" answer, and its question.
    static let notFound = load(BriefResponse<ChatAnswer>.self, "ask-notfound")
    static let notFoundQuestion = load(Asked.self, "ask-notfound").question

    // MARK: Models

    /// The signed-in app: David, with Breck on top of three quieter chats.
    /// `loading`: no chats yet, waiting on the server's first answer.
    static func app(name: String = myName, chats: [ChatSummary]? = nil, loading: Bool = false) -> AppModel {
        AppModel.preview(me: me, name: name, chats: loading ? [] : (chats ?? inbox), loading: loading)
    }

    /// The Breck chat before its first page: no messages yet, and no copy on
    /// the phone. `holds` keeps it that way (`-screen chat-loading`);
    /// otherwise it opens empty, with a catch-up that never lands, for the
    /// skim's blank window (`-screen ai-loading-blank`).
    static func emptyChatModel(holds: Bool) -> ChatModel {
        ChatModel.preview(chat: breck, myId: me, members: holds ? [] : members, messages: [],
                          catchUp: .loading, answer: .loading, delay: .zero, loading: holds)
    }

    /// The Breck chat as the app opens it with a copy kept on the phone, and
    /// no server (`-screen chat-kept`): a live ChatModel, not a canned one,
    /// that restores the copy, places it, fails to refresh offline and says
    /// so. Its catch-up fails the same way.
    static func keptChatModel() -> ChatModel {
        storeUser = me
        defer { storeUser = nil }
        DeviceStore.shared.saveThread(breckId, messages: messages, members: members)
        return ChatModel(chat: breck, myId: me)
    }

    /// The Breck chat, 302 unread. Muse Spark requests wait `delay`, then land
    /// on `catchUp` or `answer` (the fixtures unless you pass a phase; pass
    /// `.loading` to stay loading). With `asked`, it opens as if that question
    /// was already answered.
    static func chatModel(catchUp: AIPhase<BriefResponse<CatchUp>>? = nil,
                          answer: AIPhase<BriefResponse<ChatAnswer>>? = nil,
                          delay: Duration = .seconds(1.5),
                          asked: String? = nil) -> ChatModel {
        ChatModel.preview(chat: breck, myId: me, members: members, messages: messages,
                          catchUp: catchUp ?? .done(brief), answer: answer ?? .done(self.answer),
                          delay: delay, asked: asked)
    }

    /// What `ChatView(chat:myId:)` uses while previewing, so inbox → chat stays
    /// offline. Nil outside preview mode (and for chats it doesn't know).
    static func chatModel(for chatId: UUID) -> ChatModel? {
        guard isActive else { return nil }
        if chatId == breckId { return chatModel() }
        guard let other = others.first(where: { $0.chat.id == chatId }) else { return nil }
        let none = "Offline preview: only Breck Weekend has a canned catch-up."
        return ChatModel.preview(chat: other.chat, myId: me, members: other.members, messages: other.messages,
                                 catchUp: .failed(none), answer: .failed(none), delay: .seconds(1))
    }

    // MARK: The rest of the inbox

    /// Breck plus three made-up chats, newest first.
    static var inbox: [ChatSummary] { [breck] + others.map(\.chat) }

    private struct OtherChat {
        let chat: ChatSummary
        let members: [Member]
        let messages: [Message]
    }

    /// Times hang off Breck's last message, so the order never changes.
    private static let others: [OtherChat] = {
        let anchor = messages.last?.createdAt ?? .now
        return [
            other("Roommates", code: "RM8T2Q", idSuffix: 1, people: ["Nina", "Marcus"], anchor: anchor, lines: [
                ("Marcus", "plumber is coming Thursday between 8 and noon", 190),
                (myName, "I'm home Thursday morning, I'll let him in", 182),
                ("Nina", "hero 🙏", 75),
                ("Marcus", "also rent is due Friday", 62),
                ("Nina", "who keeps buying oat milk and not drinking it", 50),
            ], readThrough: 1),
            other("Capstone team", code: "CAP5T9", idSuffix: 2, people: ["Owen", "Lena", "Raj"], anchor: anchor, lines: [
                ("Lena", "draft of the methods section is in the doc", 1_700),
                ("Raj", "I'll do the lit review table tonight", 1_640),
                ("Owen", "pushed the slides, someone check slide 9 please", 1_560),
            ], readThrough: nil, unread: 41),
            other("Family", code: "FAM1LY", idSuffix: 3, people: ["Aunt Rosa", "Grandma June"], anchor: anchor, lines: [
                ("Grandma June", "Who is bringing rolls on Thanksgiving?", 4_400),
                (myName, "I've got rolls", 4_350),
                ("Aunt Rosa", "sending the casserole recipe now", 4_320),
            ], readThrough: 2),
        ]
    }()

    /// One made-up chat. `lines` are (who, what, minutes before the anchor);
    /// the reader has read through line `readThrough` (nil: none of it).
    private static func other(_ name: String, code: String, idSuffix: Int, people: [String], anchor: Date,
                              lines: [(String, String, Double)], readThrough: Int?, unread: Int? = nil) -> OtherChat {
        let chatId = UUID(uuidString: String(format: "C0000000-0000-4000-8000-%012ld", idSuffix))!
        let created = anchor.addingTimeInterval(-60 * 60 * 24 * 30)
        let cast = [(me, myName)] + people.enumerated().map { i, person in
            (UUID(uuidString: String(format: "D0000000-0000-4000-8000-0000000%02ld%03ld", idSuffix, i))!, person)
        }
        let messages = lines.enumerated().map { i, line in
            Message(id: UUID(uuidString: String(format: "E0000000-0000-4000-8000-0000000%02ld%03ld", idSuffix, i))!,
                    chatId: chatId, sender: cast.first { $0.1 == line.0 }?.0 ?? me, body: line.1,
                    createdAt: anchor.addingTimeInterval(-line.2 * 60))
        }
        let readAt = readThrough.map { messages[$0].createdAt } ?? created
        let unreadCount = unread ?? messages.filter { $0.createdAt > readAt && $0.sender != me }.count
        let last = messages.last
        let chat = ChatSummary(
            id: chatId, name: name, inviteCode: code, memberCount: cast.count, createdAt: created,
            lastMessageAt: last?.createdAt, lastMessagePreview: last?.body,
            lastMessageSenderName: last.map { m in cast.first { $0.0 == m.sender }?.1 ?? "" },
            lastReadAt: readAt, unreadCount: unreadCount)
        return OtherChat(chat: chat, members: cast.map { member($0.0, $0.1, joined: created) }, messages: messages)
    }

    // MARK: Plumbing

    private static func id(of name: String) -> UUID {
        breckCast.first { $0.name == name }?.id ?? me
    }

    private static func member(_ id: UUID, _ name: String, joined: Date) -> Member {
        Member(userId: id, joinedAt: joined, lastReadAt: joined, profile: Profile(id: id, displayName: name))
    }

    /// `{id, name, body, created_at}` rows in messages.json.
    private struct FixtureMessage: Decodable {
        let id: UUID
        let name: String
        let body: String
        let createdAt: Date
        enum CodingKeys: String, CodingKey { case id, name, body; case createdAt = "created_at" }
    }

    /// The `question` the Ask fixtures carry next to the envelope.
    private struct Asked: Decodable { let question: String }

    /// Decodes a bundled fixture with the app's own decoder, so previews go
    /// through the same code as live data. A broken fixture stops the app.
    private static func load<T: Decodable>(_ type: T.Type, _ name: String) -> T {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json") else {
            fatalError("Fixture \(name).json isn't in the app bundle")
        }
        do {
            return try JSON.decoder.decode(T.self, from: Data(contentsOf: url))
        } catch {
            fatalError("Fixture \(name).json didn't decode: \(error)")
        }
    }
}
#endif
