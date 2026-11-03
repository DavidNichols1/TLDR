//
//  KetchupApp.swift
//  Ketchup
//
//  Entry point. Signed out → SignInView; signed in → the home tabs, with
//  the inbox as the first (after a one-time "what should we call you"
//  step).
//

import SwiftUI

@main
struct KetchupApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .tint(Theme.ketchupText)
                .task { Purchases.shared.start() }  // Plans: StoreKit's transactions, from launch (Plans/Purchases.swift)
        }
    }
}
