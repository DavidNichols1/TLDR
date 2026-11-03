//
//  RootView.swift
//  TLDR
//

import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Group {
            if !app.isSignedIn {
                SignInView()
            } else if app.needsName {
                NameView()
            } else {
                ChatsListView()
            }
        }
        .animation(.default, value: app.isSignedIn)
        .animation(.default, value: app.needsName)
        .task(id: app.myId) { await app.loadMe() }
    }
}
