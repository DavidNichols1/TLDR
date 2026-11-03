//
//  PeoplePreviewScreen.swift
//  Ketchup
//
//  Settings and the people screens on fixtures, one screen per `-screen`
//  name: Settings itself (add `-section web`, `account` or `about` to
//  scroll there), Settings as the inbox opens it (a sheet), Change your
//  name, Delete account, a profile (and the same person blocked), Report
//  a message (and the thank-you), Blocked people, Chat info with a
//  blocked member, a profile or a report opened from the thread, Your
//  people (and empty), a profile that's one of your people, New chat with
//  people picked, and Invite friends. The people are the demo chat's made-up friends. Offline
//  like every preview: signing out, deleting, blocking and reporting touch
//  nothing.
//

#if DEBUG
import SwiftUI

struct PeoplePreviewScreen: View {
    enum Screen: String, CaseIterable {
        case settings
        case settingsSheet = "settings-sheet"
        case settingsName = "settings-name"
        case settingsDelete = "settings-delete"
        case settingsBlocked = "settings-blocked"
        case profile
        case profileBlocked = "profile-blocked"
        case report
        case reportSent = "report-sent"
        case infoBlocked = "info-blocked"
        case chatProfile = "chat-profile"
        case chatReport = "chat-report"
        case people
        case peopleEmpty = "people-empty"
        case profileContact = "profile-contact"
        case newChatPeople = "new-chat-people"
        case invite
    }

    static var names: [String] { Screen.allCases.map(\.rawValue) }

    /// The email previews show for the account (there's no session to read
    /// it from). example.com, never a real address.
    static let email = "david@example.com"

    let name: String
    @State private var app = PreviewData.app()
    @State private var chatModel = PreviewData.chatModel()
    @State private var newName = "Ski trip dinner"
    @State private var newPeople: Set<UUID> = [PreviewData.maya, PreviewData.theo]

    init(name: String) {
        self.name = name
        let screen = Screen(rawValue: name)
        // The inbox opens its own Settings sheet (ChatsListView). Registered,
        // not saved: it lasts for this launch only.
        if screen == .settingsSheet {
            UserDefaults.standard.register(defaults: ["KetchupOpenSettings": true])
        }
        switch screen {
        case .settingsBlocked:
            PeopleStore.shared.preview(blocked: [Self.blocked(.jordan, daysAgo: 1), Self.blocked(.sam, daysAgo: 6)])
        case .profileBlocked, .infoBlocked:
            PeopleStore.shared.preview(blocked: [Self.blocked(.jordan, daysAgo: 1)])
        case .people, .newChatPeople, .settings:
            PeopleStore.shared.preview(blocked: [], contacts: Self.contacts)
        case .profileContact:
            PeopleStore.shared.preview(blocked: [], contacts: [Self.contact(PreviewData.jordan, "Jordan")])
        default:
            PeopleStore.shared.preview(blocked: [])
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
            case .settingsBlocked:
                NavigationStack { BlockedPeopleView() }
            case .profile, .profileBlocked:
                NavigationStack {
                    ProfileView(person: Self.person(.jordan), previewShared: [PreviewData.breck])
                }
            case .report:
                ReportSheet(target: Self.reported)
            case .reportSent:
                NavigationStack { ReportView(target: Self.reported, sent: true, closesSheet: true) }
            case .infoBlocked:
                ChatInfoSheet(model: chatModel) {}
            case .chatProfile:
                NavigationStack { ChatView(model: chatModel, showing: .profile(Self.person(.jordan))) }
            case .chatReport:
                NavigationStack { ChatView(model: chatModel, showing: .report(Self.reported)) }
            case .people, .peopleEmpty:
                NavigationStack { PeopleView() }
            case .profileContact:
                NavigationStack {
                    ProfileView(person: Self.person(.jordan), previewShared: [PreviewData.breck])
                }
            case .newChatPeople:
                HomePager(previewing: .chats)
                    .sheet(isPresented: .constant(true)) {
                        NewChatSheet(name: $newName, people: Self.contacts.map(\.person), picked: $newPeople) {}
                    }
            case .invite:
                NavigationStack { InviteView() }
            case nil:
                PreviewIndex(unknown: name)
            }
        }
        .environment(app)
    }

    // MARK: Fixtures

    private enum Who { case jordan, sam }

    private static func person(_ who: Who) -> Person {
        switch who {
        case .jordan: Person(id: PreviewData.jordan, name: "Jordan")
        case .sam: Person(id: PreviewData.sam, name: "Sam")
        }
    }

    private static func blocked(_ who: Who, daysAgo: Double) -> BlockedPerson {
        let p = person(who)
        return BlockedPerson(id: p.id, displayName: p.name, avatarPath: nil,
                             blockedAt: .now.addingTimeInterval(-daysAgo * 86_400))
    }

    /// Three of the demo chat's friends, added from Breck.
    private static var contacts: [Contact] {
        [contact(PreviewData.maya, "Maya"), contact(PreviewData.priya, "Priya"), contact(PreviewData.theo, "Theo")]
    }

    private static func contact(_ id: UUID, _ name: String) -> Contact {
        Contact(id: id, displayName: name, avatarPath: nil, addedAt: .now.addingTimeInterval(-86_400), sharedChats: 1)
    }

    /// One of Jordan's messages in the demo chat.
    private static var reported: ReportTarget {
        let message = PreviewData.messages.first { $0.sender == PreviewData.jordan } ?? PreviewData.messages[0]
        return .message(message, from: person(.jordan))
    }
}
#endif
