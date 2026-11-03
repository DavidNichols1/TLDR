//
//  KetchupApp.swift
//  Ketchup
//
//  Entry point. Signed out → SignInView; signed in → the inbox (after a
//  one-time "what should we call you" step).
//

import SwiftUI

@main
struct KetchupApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .tint(Theme.accent)
        }
    }
}
