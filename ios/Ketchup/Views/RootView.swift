//
//  RootView.swift
//  Ketchup
//

import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        #if DEBUG
        if let screen = PreviewData.screen {
            // Offline preview mode (`-screen <name>`): see Debug/PreviewData.swift.
            PreviewRouter(name: screen)
        } else {
            live
        }
        #else
        live
        #endif
    }

    private var live: some View {
        Group {
            if !app.isSignedIn {
                SignInView()
            } else if app.needsName {
                NameView()
            } else {
                HomeTabs()
            }
        }
        .motion(Motion.settle, value: app.isSignedIn)
        .motion(Motion.settle, value: app.needsName)
        .background(Theme.cream)
        .task(id: app.myId) { await app.loadMe() }
        .task(id: app.myId) { await PlanStore.shared.signedIn(app.myId) }  // Plans: your plan, at sign-in (Plans/PlanStore.swift)
        .task(id: app.myId) { await TermsStore.shared.signedIn(app.myId) }  // Terms: agreed yet? (Terms/Terms.swift)
        .fullScreenCover(isPresented: termsSheet) {
            TermsSheet().environment(app)
        }
    }

    /// The one-time terms sheet, while someone signed in hasn't agreed to this version.
    private var termsSheet: Binding<Bool> {
        Binding(get: { app.isSignedIn && TermsStore.shared.showsSheet }, set: { _ in })
    }
}
