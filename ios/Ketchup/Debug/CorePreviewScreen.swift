//
//  CorePreviewScreen.swift
//  Ketchup
//
//  The chat side of the app on fixtures, one screen per `-screen` name:
//  sign-in, the inbox (full and empty), the name step, the Breck chat and
//  its info sheet. Sheets are shown full screen.
//

#if DEBUG
import SwiftUI

struct CorePreviewScreen: View {
    enum Screen: String, CaseIterable {
        case signIn = "signin"
        case inbox
        case inboxEmpty = "inbox-empty"
        case name
        case chat
        case info
    }

    static var names: [String] { Screen.allCases.map(\.rawValue) }

    let name: String
    @State private var app: AppModel
    @State private var chatModel = PreviewData.chatModel()

    init(name: String) {
        self.name = name
        switch Screen(rawValue: name) {
        case .inboxEmpty: _app = State(initialValue: PreviewData.app(chats: []))
        // The name step prefills what sign-up picked: the email's first part.
        case .name: _app = State(initialValue: PreviewData.app(name: "david"))
        default: _app = State(initialValue: PreviewData.app())
        }
    }

    var body: some View {
        Group {
            switch Screen(rawValue: name) {
            case .signIn:
                SignInView()
            case .inbox, .inboxEmpty:
                ChatsListView()
            case .name:
                NameView()
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
