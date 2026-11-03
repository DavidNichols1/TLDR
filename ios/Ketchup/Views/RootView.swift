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
    }
}
