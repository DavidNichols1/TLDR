//
//  InstagramCatchUpScreen.swift
//  Ketchup
//
//  EXPERIMENTAL, NOT RELEASED: "Catch me up" for an Instagram DM thread.
//  The user signs in on Instagram's own page and opens a chat. The button
//  reads that one thread off the page and runs the same Muse Spark catch-up
//  as Ketchup's own chats (edge function catch-up-text). Nothing from the
//  chat is stored, on the phone or on the server.
//
//  Instagram's terms don't allow automated reading, so this stays out of the
//  released app unless Meta is fine with it. Ketchup's own chat never
//  depends on it. Styling is minimal on purpose: it gets the app's design
//  once the redesign lands.
//

import SwiftUI

/// The inbox's one way in (ChatsListView's toolbar).
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
            InstagramCatchUpScreen().environment(app)
        }
    }
}

struct InstagramCatchUpScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    /// Made on first appear, not in init: SwiftUI may build this view many
    /// times, and each browser owns a web view.
    @State private var browser: InstagramBrowser?
    @State private var step: Step = .idle
    @State private var result: IGCatchUpResult?
    @State private var error: String?
    @AppStorage("instagram.introSeen") private var introSeen = false

    private enum Step: Equatable { case idle, reading, thinking(Int) }

    private var readerName: String { app.me?.displayName ?? "Me" }

    var body: some View {
        NavigationStack {
            Group {
                if let browser {
                    InstagramWebView(webView: browser.webView)
                        .overlay(alignment: .top) {
                            if browser.isLoading { ProgressView().padding(8) }
                        }
                        .overlay(alignment: .bottom) {
                            if browser.isThread { catchUpButton(browser).padding(.bottom, 84) }
                        }
                } else {
                    Color.clear
                }
            }
            .overlay { if !introSeen { intro } }
            .navigationTitle("Instagram")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
        }
        .onAppear(perform: start)
        .sheet(item: $result) { InstagramResultView(result: $0, readerName: readerName) }
        .alert("Couldn't catch you up", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
    }

    private func start() {
        guard browser == nil else { return }
        let b = InstagramBrowser()
        browser = b
        #if DEBUG
        // `-KetchupInstagramFixture YES` opens the synthetic test thread instead.
        if UserDefaults.standard.bool(forKey: "KetchupInstagramFixture") { b.openFixture(); return }
        #endif
        b.openInbox()
    }

    // MARK: Catch up

    private func catchUpButton(_ browser: InstagramBrowser) -> some View {
        Button { Task { await catchUp(browser) } } label: {
            HStack(spacing: 8) {
                if step == .idle { Image(systemName: "sparkles") } else { ProgressView().tint(.white) }
                Text(buttonTitle)
            }
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(LinearGradient(colors: [.indigo, .purple, .pink], startPoint: .leading, endPoint: .trailing),
                        in: Capsule())
            .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .disabled(step != .idle)
    }

    private var buttonTitle: String {
        switch step {
        case .idle: return "Catch me up on this chat"
        case .reading: return "Reading this chat…"
        case .thinking(let n): return "Muse Spark is reading \(n) messages…"
        }
    }

    private func catchUp(_ browser: InstagramBrowser) async {
        guard step == .idle else { return }
        step = .reading
        defer { step = .idle }
        do {
            let thread = try await browser.readThread(readerName: readerName)
            step = .thinking(thread.messages.count)
            let reply = try await InstagramAPI.catchUp(thread, readerName: readerName)
            if reply.empty == true { error = "There are no messages here to catch up on."; return }
            guard let brief = reply.result else { throw APIError.badResponse }
            result = IGCatchUpResult(thread: thread, brief: brief, latencyMs: reply.latencyMs)
        } catch {
            self.error = InstagramError.message(for: error)
        }
    }

    // MARK: Chrome

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Close", systemImage: "xmark") { dismiss() }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button("Back", systemImage: "chevron.backward") { browser?.goBack() }
                .disabled(browser?.canGoBack != true)
            Menu {
                Button("Instagram inbox", systemImage: "tray") { browser?.openInbox() }
                Button("Reload", systemImage: "arrow.clockwise") { browser?.reload() }
                Button("How this works", systemImage: "info.circle") { introSeen = false }
                #if DEBUG
                Button("Test thread (fixture)", systemImage: "testtube.2") { browser?.openFixture() }
                #endif
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    private var intro: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                Label("Experimental", systemImage: "flask")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.orange)
                Text("Catch up on an Instagram chat")
                    .font(.title2.bold())
                VStack(alignment: .leading, spacing: 12) {
                    point("person.badge.key", "Sign in on Instagram's own page. Ketchup never sees your password.")
                    point("hand.tap", "Open a chat and tap Catch me up. Ketchup reads only that chat, only when you tap.")
                    point("sparkles", "The messages, your friends' too, go to Muse Spark to summarize. Nothing is saved.")
                    point("exclamationmark.triangle", "Not in the released app. Instagram's terms don't allow this, so it only ships if Meta is fine with it.")
                }
                Button { introSeen = true } label: {
                    Text("Got it").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(24)
            .background(.background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(20)
        }
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }
}
