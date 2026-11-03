//
//  PeoplePreviewScreen.swift
//  Ketchup
//
//  Settings and its pages on fixtures, one screen per `-screen` name:
//  Settings itself (add `-section web`, `account` or `about` to scroll
//  there), Settings as the inbox opens it (a sheet), Change your name, and
//  Delete account. Offline like every preview: signing out, deleting and
//  renaming touch nothing.
//

#if DEBUG
import SwiftUI

struct PeoplePreviewScreen: View {
    enum Screen: String, CaseIterable {
        case settings
        case settingsSheet = "settings-sheet"
        case settingsName = "settings-name"
        case settingsDelete = "settings-delete"
    }

    static var names: [String] { Screen.allCases.map(\.rawValue) }

    /// The email previews show for the account (there's no session to read
    /// it from). example.com, never a real address.
    static let email = "david@example.com"

    let name: String
    @State private var app = PreviewData.app()

    init(name: String) {
        self.name = name
        // The inbox opens its own Settings sheet (ChatsListView). Registered,
        // not saved: it lasts for this launch only.
        if Screen(rawValue: name) == .settingsSheet {
            UserDefaults.standard.register(defaults: ["KetchupOpenSettings": true])
        }
    }

    var body: some View {
        Group {
            switch Screen(rawValue: name) {
            case .settings:
                SettingsView { _ in }
            case .settingsSheet:
                HomePager(previewing: .chats)
            case .settingsName:
                NavigationStack { EditNameView() }
            case .settingsDelete:
                NavigationStack { DeleteAccountView {} }
            case nil:
                PreviewIndex(unknown: name)
            }
        }
        .environment(app)
    }
}
#endif
