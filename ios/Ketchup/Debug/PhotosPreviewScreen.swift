//
//  PhotosPreviewScreen.swift
//  Ketchup
//
//  Photos on fixtures, one screen per `-screen` name. Profile photos: the
//  cropper framing a picked photo, the inbox with David's photo on the
//  account button, the Breck chat with photos by each sender's run, and its
//  members. Photos in chats: the end of Breck with photos in it, a photo of
//  David's on its way up, one waiting in the composer, and the viewer. Muse
//  Spark reading them: a brief and an answer that cite Maya's photo of the
//  door code. The photos are made up (Debug/PreviewPhotos.swift); Sam keeps
//  his monogram, to show the fallback.
//

#if DEBUG
import SwiftUI

struct PhotosPreviewScreen: View {
    enum Screen: String, CaseIterable {
        case crop = "photo-crop"
        case inbox = "photo-inbox"
        case chat = "photo-chat"
        case info = "photo-info"
        case thread = "photo-thread"
        case sending = "photo-sending"
        case attach = "photo-attach"
        case viewer = "photo-viewer"
        case catchUp = "photo-catchup"
        case answer = "photo-answer"
    }

    /// Maya's photo of the door code, which the brief and the answer cite.
    static let doorPhoto = UUID(uuidString: "F0000000-0000-4000-8000-000000000004")!

    static var names: [String] { Screen.allCases.map(\.rawValue) }

    let name: String
    @State private var app: AppModel
    @State private var chatModel: ChatModel

    init(name: String) {
        self.name = name
        let app = PreviewData.app()
        app.setAvatarPath(PreviewPhotos.avatarPath(for: PreviewData.myName))
        _app = State(initialValue: app)
        let members = PreviewData.members.map { member in
            Member(userId: member.userId, joinedAt: member.joinedAt, lastReadAt: member.lastReadAt,
                   profile: Profile(id: member.userId, displayName: member.name,
                                    avatarPath: PreviewPhotos.avatarPath(for: member.name)))
        }
        let screen = Screen(rawValue: name)
        let withPhotos = screen.map { [.thread, .sending, .attach, .viewer].contains($0) } ?? false
        let citing = screen.map { [.catchUp, .answer].contains($0) } ?? false
        _chatModel = State(initialValue: withPhotos || citing
            ? Self.photoChat(members: members, unread: citing, asked: screen == .answer)
            : ChatModel.preview(chat: PreviewData.breck, myId: PreviewData.me, members: members,
                                messages: PreviewData.messages, catchUp: .done(PreviewData.brief),
                                answer: .done(PreviewData.answer), delay: .seconds(1.5)))
        // The pager's other pages stay on their synthetic threads (see CorePreviewScreen).
        UserDefaults.standard.register(defaults: ["KetchupInstagramFixture": true, "KetchupSnapchatFixture": true])
    }

    var body: some View {
        Group {
            switch Screen(rawValue: name) {
            case .crop:
                AvatarCropper(image: PreviewPhotos.landscape()) { _ in
                    try await Task.sleep(for: .seconds(1))
                }
            case .inbox:
                HomePager(previewing: .chats)
            case .chat, .thread:
                NavigationStack {
                    ChatView(model: chatModel)
                }
            case .info:
                ChatInfoSheet(model: chatModel) {}
            case .sending:
                NavigationStack {
                    ChatView(model: chatModel)
                }
                .task {
                    // Slow enough to catch the ring partway round.
                    PhotoUploads.shared.previewDuration = .seconds(20)
                    try? await Task.sleep(for: .seconds(1))
                    if let photo = PreviewPhotos.prepared("pickles") {
                        chatModel.send(photo, caption: "pickles approves of the snow")
                    }
                }
            case .attach:
                NavigationStack {
                    ChatView(model: chatModel, attaching: PreviewPhotos.prepared("pickles"),
                             caption: "pickles approves of the snow")
                }
            case .viewer:
                if let cabin = chatModel.messages.first(where: { $0.imagePath == "preview/cabin.jpg" }) {
                    PhotoViewer(message: cabin, senderName: chatModel.name(of: cabin.sender))
                }
            case .catchUp:
                CatchUpSheet(model: chatModel, refs: refs)
            case .answer:
                AskSheet(model: chatModel, refs: refs)
            case nil:
                PreviewIndex(unknown: name)
            }
        }
        .environment(app)
    }

    /// Ref chips as in the chat: who said it, and a photo's thumbnail.
    private var refs: RefContext {
        RefContext(preview: { [chatModel] in chatModel.preview($0) }, jump: { _ in },
                   photo: { [chatModel] id in chatModel.messages.first { $0.id == id }?.smallPhoto })
    }

    /// Breck, then four photos: Maya's cabin with a caption, Jordan's
    /// mountains without one, Maya's view, and Maya's door code. Read to the
    /// end, or all unread with a brief (or an answer) that cites the door code.
    private static func photoChat(members: [Member], unread: Bool = false, asked: Bool = false) -> ChatModel {
        let last = PreviewData.messages.last?.createdAt ?? .now
        var chat = PreviewData.breck
        if !unread {
            chat.unreadCount = 0
            chat.lastReadAt = last.addingTimeInterval(3600)
        }
        let photos: [(id: String, sender: UUID, photo: String, caption: String, after: TimeInterval)] = [
            ("F0000000-0000-4000-8000-000000000001", PreviewData.maya, "cabin", "the cabin!!", 600),
            ("F0000000-0000-4000-8000-000000000002", PreviewData.jordan, "mountains", "", 900),
            ("F0000000-0000-4000-8000-000000000003", PreviewData.maya, "mountains", "view from the deck", 960),
            (doorPhoto.uuidString, PreviewData.maya, "door", "the host sent the door code early 🙌", 1200),
        ]
        let messages = PreviewData.messages + photos.compactMap { item in
            guard let photo = PreviewPhotos.chatPhoto(item.photo) else { return nil }
            return Message(id: UUID(uuidString: item.id)!, chatId: chat.id, sender: item.sender, body: item.caption,
                           createdAt: last.addingTimeInterval(item.after),
                           imagePath: photo.path, imageWidth: photo.width, imageHeight: photo.height)
        }
        return ChatModel.preview(chat: chat, myId: PreviewData.me, members: members, messages: messages,
                                 catchUp: .done(citingBrief), answer: .done(citingAnswer),
                                 delay: .seconds(1.5), asked: asked ? "what's the code for the cabin door?" : nil)
    }

    /// The fixture brief with what Muse Spark found in the door photo on top
    /// (its words from a real call on the demo chat, Nov 3, 2026).
    private static var citingBrief: BriefResponse<CatchUp> {
        let base = PreviewData.brief
        guard let brief = base.result else { return base }
        let door = CatchUp.Item(text: "Maya shared the cabin door code early: 4471, hit # after", refs: [doorPhoto])
        return BriefResponse(kind: base.kind, empty: base.empty, cached: base.cached,
                             result: CatchUp(tldr: brief.tldr, highlights: [door] + brief.highlights, plans: brief.plans,
                                             openQuestions: brief.openQuestions, owes: brief.owes, forYou: brief.forYou),
                             model: base.model, messageCount: base.messageCount, latencyMs: base.latencyMs,
                             until: base.until, error: base.error)
    }

    /// Ask's real answer to "what's the code for the cabin door?" (Nov 3, 2026).
    private static var citingAnswer: BriefResponse<ChatAnswer> {
        BriefResponse(kind: "ask", empty: false, cached: false,
                      result: ChatAnswer(answer: "4471, hit # after. Maya posted it from the host.", found: true,
                                         refs: [doorPhoto]),
                      model: "muse-spark-1.3", messageCount: 304, latencyMs: 3279, until: nil, error: nil)
    }
}
#endif
