//
//  InstagramEntry.swift
//  Ketchup
//
//  EXPERIMENTAL, NOT RELEASED. The inbox's way into the Instagram page
//  (ChatsListView's toolbar), until the signed-in home becomes a pager with
//  a WebChatTab per source. It shows the same tab full screen, with Done.
//

import SwiftUI

struct InstagramToolbarItem: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) { InstagramEntryButton() }
    }
}

private struct InstagramEntryButton: View {
    @Environment(AppModel.self) private var app
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            Label("Catch up on Instagram", systemImage: "camera")
        }
        .fullScreenCover(isPresented: $open) {
            WebChatTab(source: .instagram) { open = false }
                .environment(app)
        }
    }
}
