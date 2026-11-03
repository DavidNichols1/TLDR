//
//  PhotosPreviewScreen.swift
//  Ketchup
//
//  Profile photos on fixtures, one screen per `-screen` name: the cropper
//  framing a picked photo, the inbox with David's photo on the account
//  button, the Breck chat with photos by each sender's run, and its
//  members. The photos are made up (Debug/PreviewPhotos.swift); Sam keeps
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
    }

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
        _chatModel = State(initialValue: ChatModel.preview(
            chat: PreviewData.breck, myId: PreviewData.me, members: members, messages: PreviewData.messages,
            catchUp: .done(PreviewData.brief), answer: .done(PreviewData.answer), delay: .seconds(1.5)))
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
            case .chat:
                NavigationStack {
                    ChatView(model: chatModel)
                }
            case .info:
                ChatInfoSheet(model: chatModel) {}
            case nil:
                PreviewIndex(unknown: name)
            }
        }
        .environment(app)
    }
}
#endif
