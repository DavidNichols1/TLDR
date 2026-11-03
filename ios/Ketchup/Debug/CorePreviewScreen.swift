//
//  CorePreviewScreen.swift
//  Ketchup
//
//  The chat side of the app on fixtures, one screen per `-screen` name:
//  sign-in (email and code), the name step, the inbox (full and empty)
//  with its New chat and Join sheets, the Breck chat (and a jump to a
//  cited message), its info sheet, and the app icon. The info sheet is
//  shown full screen.
//

#if DEBUG
import SwiftUI

struct CorePreviewScreen: View {
    enum Screen: String, CaseIterable {
        case signIn = "signin"
        case signInCode = "signin-code"
        case name
        case inbox
        case inboxEmpty = "inbox-empty"
        case newChat = "new-chat"
        case join
        case chat
        case chatJump = "chat-jump"
        case info
        case icon
    }

    static var names: [String] { Screen.allCases.map(\.rawValue) }

    /// Maya's "so the Airbnb is now $540 total = $90 each", a message the
    /// catch-up cites, a good way up the thread.
    static let jumpTarget = UUID(uuidString: "6fe6a3cc-7a99-5aa3-a3dd-be8a6a18adb5")!

    let name: String
    @State private var app: AppModel
    @State private var chatModel = PreviewData.chatModel()
    @State private var draft = ""

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
            case .signInCode:
                SignInView(previewCodeFor: "david@example.com", code: "4821", cooldown: 42)
            case .name:
                NameView()
            case .inbox, .inboxEmpty:
                ChatsListView()
            case .newChat:
                ChatsListView()
                    .sheet(isPresented: .constant(true)) {
                        NewChatSheet(name: $draft) {}
                    }
            case .join:
                ChatsListView()
                    .sheet(isPresented: .constant(true)) {
                        JoinChatSheet(code: $draft) {}
                    }
            case .chat:
                NavigationStack {
                    ChatView(model: chatModel)
                }
            case .chatJump:
                NavigationStack {
                    ChatView(model: chatModel, jumpingTo: Self.jumpTarget)
                }
            case .info:
                ChatInfoSheet(model: chatModel) {}
            case .icon:
                AppIconPreview()
            case nil:
                PreviewIndex(unknown: name)
            }
        }
        .environment(app)
    }
}

// MARK: - App icon

/// The app icon: a cream ketchup drop with its shine on ketchup red, drawn
/// from `KetchupDrop`, so the icon and the logo are the same shape.
struct AppIconArtwork: View {
    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                Color(uiColor: UIColor(hex: 0xD7372B))
                KetchupDrop()
                    .fill(Color(uiColor: UIColor(hex: 0xFBF5EA)))
                    .padding(side * 0.15)
                DropShine()
                    .fill(Color(uiColor: UIColor(hex: 0xD7372B)))
                    .padding(side * 0.15)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// The 1024 x 1024 PNG for Assets.xcassets, opaque (App Store icons
    /// can't have an alpha channel).
    static func png() -> Data? {
        let renderer = ImageRenderer(content: AppIconArtwork().frame(width: 1024, height: 1024))
        renderer.scale = 1
        renderer.isOpaque = true
        return renderer.uiImage?.pngData()
    }
}

/// `-screen icon`: the icon big and at home-screen sizes, and a fresh
/// 1024 px PNG written to the app's Documents folder as AppIcon.png
/// (`xcrun simctl get_app_container <udid> com.vibetemp.ketchup data`).
private struct AppIconPreview: View {
    @State private var savedTo: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Kicker("App icon")
                    Text("The drop")
                        .font(.serif(.largeTitle))
                        .foregroundStyle(Theme.ink)
                }
                icon(size: 240)
                HStack(alignment: .bottom, spacing: 20) {
                    ForEach([60, 40, 29] as [CGFloat], id: \.self) { size in
                        VStack(spacing: 6) {
                            icon(size: size)
                            Text("\(Int(size)) pt")
                                .font(.mono(.caption2))
                                .foregroundStyle(Theme.inkSoft)
                        }
                    }
                }
                if let savedTo {
                    Text(savedTo)
                        .font(.mono(.caption2))
                        .foregroundStyle(Theme.inkSoft)
                        .textSelection(.enabled)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.cream)
        .task { save() }
    }

    /// The icon as the home screen masks it: a continuous rounded square.
    private func icon(size: CGFloat) -> some View {
        AppIconArtwork()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous))
    }

    private func save() {
        guard let data = AppIconArtwork.png(),
              let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let url = folder.appending(path: "AppIcon.png")
        if (try? data.write(to: url)) != nil { savedTo = url.path }
    }
}
#endif
