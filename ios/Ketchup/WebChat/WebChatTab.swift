//
//  WebChatTab.swift
//  Ketchup
//
//  EXPERIMENTAL, NOT RELEASED. One tab of the signed-in home per source
//  (`WebChatTab(source: .instagram)`): the site's own web page under a slim
//  bar, and Catch me up for the thread that's open, a small ketchup circle
//  on the right edge. No navigation stack and nothing to dismiss, so it sits
//  in a tab as it is. The site's terms don't allow reading chats this way,
//  so it stays out of the released app unless the site's owner is fine
//  with it.
//

import SwiftUI

struct WebChatTab: View {
    let source: WebChatSource
    /// Only for a page shown full screen: adds Done to the bar.
    var close: (() -> Void)? = nil

    var body: some View {
        WebChatPage(source: source, close: close)
    }
}

private struct WebChatPage: View {
    let source: WebChatSource
    let close: (() -> Void)?

    @Environment(AppModel.self) private var app: AppModel?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Made on first appear, not in init: SwiftUI may build this view many
    /// times, and each browser owns a web view.
    @State private var browser: WebChatBrowser?
    @State private var reading = false
    @State private var session: WebCatchUp?
    @State private var showSaved = false
    @State private var failure: Failure?
    @State private var notice: String?
    @AppStorage private var introSeen: Bool

    /// A read that didn't work, and the pick to try again.
    private struct Failure: Equatable {
        let message: String
        let last: Int
    }

    /// The page doesn't say what's unread, so the button asks how far back.
    static let windows = [30, 80, 120]

    init(source: WebChatSource, close: (() -> Void)?) {
        self.source = source
        self.close = close
        _introSeen = AppStorage(wrappedValue: false, "webchat.\(source.id).introSeen")
    }

    /// How the chat names the reader. Muse Spark writes it, CatchUpContent
    /// turns it into "You".
    private var readerName: String { app?.me?.displayName ?? "Me" }

    var body: some View {
        VStack(spacing: 0) {
            WebChatBar(title: source.name, close: close) {
                if let browser {
                    if browser.isLoading {
                        ProgressView()
                            .tint(Theme.inkSoft)
                    }
                    WebChatBarButton(symbol: "chevron.backward", label: "Back") { browser.goBack() }
                        .disabled(!browser.canGoBack)
                    menu(browser)
                }
            }
            ZStack(alignment: .bottom) {
                if let browser {
                    WebChatWebView(webView: browser.webView, layoutWidth: source.desktop?.width)
                } else {
                    Theme.cream
                }
                // On the right edge, just above the site's message box.
                VStack(alignment: .trailing, spacing: 12) {
                    if let failure {
                        AIErrorCard(message: failure.message, note: "Nothing from the chat was saved.", prominent: false) {
                            if let browser { Task { await catchUp(browser, last: failure.last) } }
                        }
                        .transition(.rise(reduceMotion: reduceMotion))
                    }
                    if let browser, browser.isThread {
                        catchUpButton(browser)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 16)
                .padding(.bottom, 76)
            }
        }
        .background(Theme.cream)
        .overlay {
            if !introSeen {
                WebChatIntro(source: source) { introSeen = true }
                    .transition(.opacity)
            }
        }
        .motion(Motion.settle, value: failure)
        .motion(Motion.settle, value: reading)
        .motion(Motion.fade, value: introSeen)
        .onAppear(perform: start)
        .onChange(of: browser?.url) { _, _ in failure = nil }
        // Settings signed this site out of Ketchup: start over at its sign-in page.
        .onReceive(NotificationCenter.default.publisher(for: .webChatForgotten)) { note in
            if note.object as? String == source.id { browser?.openStart() }
        }
        .sheet(item: $session) { WebChatSheet(session: $0) }
        .sheet(isPresented: $showSaved) { SavedBriefsSheet(place: .web(source.id), title: source.name) }
        .alert("Done", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(notice ?? "")
        }
    }

    private func start() {
        guard browser == nil else { return }
        let b = WebChatBrowser(source: source)
        browser = b
        #if DEBUG
        // `-KetchupInstagramFixture YES` (`-KetchupSnapchatFixture YES`) opens the synthetic test thread instead.
        if UserDefaults.standard.bool(forKey: "Ketchup\(source.name)Fixture"), let fixture = source.fixtures.first {
            b.open(fixture)
            return
        }
        #endif
        b.openStart()
    }

    // MARK: Catch me up

    /// The page's one ketchup thing: a small circle with the drop, so it
    /// covers little of the chat. It picks how many of the newest messages
    /// to read.
    private func catchUpButton(_ browser: WebChatBrowser) -> some View {
        Menu {
            Section("Catch me up on the") {
                ForEach(Self.windows, id: \.self) { n in
                    Button("Last \(n) messages") { Task { await catchUp(browser, last: n) } }
                }
            }
        } label: {
            CatchUpCircle(reading: reading)
        }
        .menuOrder(.fixed)
        .disabled(reading)
        .accessibilityLabel(reading ? "Reading the chat" : "Catch me up")
        .accessibilityHint("Pick how many of the newest messages to read")
    }

    private func catchUp(_ browser: WebChatBrowser, last: Int) async {
        guard !reading else { return }
        reading = true
        failure = nil
        defer { reading = false }
        do {
            let thread = try await browser.readThread(readerName: readerName, last: last)
            session = WebCatchUp(thread: thread, readerName: readerName)
        } catch {
            failure = Failure(message: WebChatError.message(for: error), last: last)
        }
    }

    // MARK: Menu

    private func menu(_ browser: WebChatBrowser) -> some View {
        Menu {
            Button("\(source.name) inbox", systemImage: "tray") { browser.openStart() }
            Button("Earlier catch-ups", systemImage: "clock.arrow.circlepath") { showSaved = true }
            Button("Reload", systemImage: "arrow.clockwise") { browser.reload() }
            Button("How this works", systemImage: "info.circle") { introSeen = false }
            #if DEBUG
            Section("Testing") {
                ForEach(source.fixtures, id: \.self) { fixture in
                    Button(fixture.title, systemImage: "testtube.2") { browser.open(fixture) }
                }
                if source.outlineScript != nil {
                    Button("Save page outline (no text)", systemImage: "list.bullet.indent") {
                        Task {
                            do {
                                let file = try await browser.savePageOutline()
                                notice = "Saved the redacted outline to \(file.lastPathComponent) in the app's tmp folder."
                            } catch {
                                notice = WebChatError.message(for: error)
                            }
                        }
                    }
                }
            }
            #endif
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 40, height: 40)
                .contentShape(.rect)
        }
        .accessibilityLabel("More")
    }
}

// MARK: - Pieces

/// The Catch me up button's face: a ketchup circle with the drop. While the
/// chat is read it opens into a pill with a spinner and "Reading the chat",
/// then closes again.
private struct CatchUpCircle: View {
    let reading: Bool

    @ScaledMetric(relativeTo: .title3) private var size: CGFloat = 54

    var body: some View {
        // Grows with the text size, to a point: it shouldn't hide the chat.
        let side = min(size, 72)
        HStack(spacing: 10) {
            if reading {
                ProgressView()
                    .tint(Theme.onKetchup)
                Text("Reading the chat")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .fixedSize()
            } else {
                KetchupDrop()
                    .fill(Theme.onKetchup)
                    .frame(width: side * 0.44, height: side * 0.44)
            }
        }
        .foregroundStyle(Theme.onKetchup)
        .padding(.horizontal, reading ? 18 : 0)
        .frame(minWidth: side, minHeight: side)
        .background(Theme.ketchup, in: Capsule())
        .contentShape(Capsule())
    }
}

/// The slim bar over the site: its name in New York, a quiet "Experimental",
/// and the page's own buttons on the right.
struct WebChatBar<Trailing: View>: View {
    let title: String
    var close: (() -> Void)? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: title)
                    .font(.serif(.title3))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Kicker("Experimental")
            }
            Spacer(minLength: 8)
            trailing()
            if let close {
                Button("Done", action: close)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .padding(.leading, 8)
                    .buttonStyle(.pressable)
            }
        }
        .padding(.leading, 20)
        .padding(.trailing, 12)
        .padding(.vertical, 8)
        .background(Theme.cream)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.rule).frame(height: 1)
        }
    }
}

/// An icon button for the bar: ink, 40 pt to tap.
struct WebChatBarButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 40, height: 40)
                .contentShape(.rect)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(label)
    }
}

/// The first visit: what happens, plainly, before anyone signs in.
struct WebChatIntro: View {
    let source: WebChatSource
    let done: () -> Void

    var body: some View {
        ZStack {
            Theme.cream.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Kicker("Experimental")
                    Text("Catch up on your \(source.name) chats")
                        .font(.serif(.title))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 14) {
                        point("person.badge.key", "Sign in on \(source.name)'s own page. Ketchup never sees your password.")
                        point("hand.tap", "Open a chat, tap the ketchup drop, and pick the last 30, 80 or 120 messages. Ketchup reads only that chat, only when you tap.")
                        point("text.bubble", "Those messages, your friends' too, go to \(Theme.modelName) to sum up. The catch-up stays on this phone until you delete it, never on Ketchup's server.")
                        if let note = source.note {
                            point("plus.magnifyingglass", note)
                        }
                        point("exclamationmark.triangle", "Not in the released app. \(source.name)'s terms don't allow this, so it only ships if \(source.owner) is fine with it.")
                    }
                    Button("Got it", action: done)
                        .buttonStyle(.ketchup)
                        .padding(.top, 4)
                }
                .paperCard(padding: 22)
                .padding(20)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.inkSoft)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
