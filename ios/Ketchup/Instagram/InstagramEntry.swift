//
//  InstagramEntry.swift
//  Ketchup
//
//  EXPERIMENTAL, NOT RELEASED. The inbox's way into the web chats
//  (ChatsListView's toolbar), until the signed-in home becomes a pager with
//  a WebChatTab per source. A menu of the sources; each shows its tab full
//  screen, with Done.
//

import SwiftUI

struct InstagramToolbarItem: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) { InstagramEntryButton() }
    }
}

private struct InstagramEntryButton: View {
    @Environment(AppModel.self) private var app
    @State private var open: WebChatSource?

    var body: some View {
        Menu {
            ForEach(WebChatSource.all) { source in
                Button("Catch up on \(source.name)") { open = source }
            }
        } label: {
            Label("Catch up on another app", systemImage: "camera")
        }
        .fullScreenCover(item: $open) { source in
            WebChatTab(source: source) { open = nil }
                .environment(app)
        }
    }
}
