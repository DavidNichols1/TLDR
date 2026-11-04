//
//  TermsPreviewScreen.swift
//  Ketchup
//
//  The password sign-in and the terms on fixtures, one screen per `-screen`
//  name: the password path, the same with a wrong password's message, and
//  the one-time terms sheet over the home, plus `terms-offline`, which
//  presses Agree 1 s in (an offline preview never reaches the server, so it
//  shows the try-again state). `signin` itself shows the terms line.
//

#if DEBUG
import SwiftUI

struct TermsPreviewScreen: View {
    enum Screen: String, CaseIterable {
        case signInPassword = "signin-password"
        case signInPasswordError = "signin-password-error"
        case terms
        case termsOffline = "terms-offline"
    }

    static var names: [String] { Screen.allCases.map(\.rawValue) }

    let name: String
    @State private var app = PreviewData.app()

    var body: some View {
        Group {
            switch Screen(rawValue: name) {
            case .signInPassword:
                SignInView(previewPasswordFor: "david@example.com")
            case .signInPasswordError:
                SignInView(previewPasswordFor: "david@example.com", error: "That email and password don't match.")
            case .terms, .termsOffline:
                HomeTabs(previewing: .chats)
                    .fullScreenCover(isPresented: .constant(true)) {
                        TermsSheet()
                            .environment(app)
                            .task {
                                guard Screen(rawValue: name) == .termsOffline else { return }
                                try? await Task.sleep(for: .seconds(1))
                                await TermsStore.shared.agree()
                            }
                    }
            case nil:
                PreviewIndex(unknown: name)
            }
        }
        .environment(app)
    }
}
#endif
