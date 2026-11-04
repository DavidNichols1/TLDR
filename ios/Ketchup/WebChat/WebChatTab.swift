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
    /// False while another tab of the home is showing (this one is kept, hidden).
    var active = true

    var body: some View {
        WebChatPage(source: source, close: close, active: active)
    }
}

private struct WebChatPage: View {
    let source: WebChatSource
    let close: (() -> Void)?
    let active: Bool

    @Environment(AppModel.self) private var app: AppModel?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    /// Made on first appear, not in init: SwiftUI may build this view many
    /// times, and each browser owns a web view.
    @State private var browser: WebChatBrowser?
    @State private var reading = false
    /// "Until I stop scrolling" while it reads.
    @State private var following: WebFollow?
    @State private var session: WebCatchUp?
    @State private var showSaved = false
    @State private var failure: Failure?
    @State private var notice: String?
    @AppStorage private var introSeen: Bool

    /// What the Catch me up menu picked.
    enum Pick: Equatable {
        case last(Int)
        case untilStop
    }

    /// A read that didn't work, and the pick to try again.
    private struct Failure: Equatable {
        let message: String
        let pick: Pick
    }

    /// The page doesn't say what's unread, so the button asks how far back.
    static let windows = [10, 30, 80, 120]

    init(source: WebChatSource, close: (() -> Void)?, active: Bool) {
        self.source = source
        self.close = close
        self.active = active
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
                    // Its pages and sheets would cover the chat while it's being read.
                    menu(browser)
                        .disabled(following != nil)
                }
            }
            ZStack(alignment: .bottom) {
                if let browser {
                    WebChatWebView(webView: browser.webView, layoutWidth: source.desktop?.width)
                } else {
                    Theme.cream
                }
                // On the right edge, just above the site's message box. While
                // following, the panel takes the bottom instead: nobody types then.
                VStack(alignment: .trailing, spacing: 12) {
                    if let failure {
                        AIErrorCard(message: failure.message, note: "Nothing from the chat was saved.", prominent: false) {
                            if let browser { Task { await run(failure.pick, browser) } }
                        }
                        .transition(.rise(reduceMotion: reduceMotion))
                    }
                    if let following {
                        FollowingPanel(follow: following)
                            .transition(.rise(reduceMotion: reduceMotion))
                    } else if let browser, browser.isThread {
                        catchUpButton(browser)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, following == nil ? 16 : 10)
                .padding(.bottom, following == nil ? 76 : 10)
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
        .motion(Motion.settle, value: following == nil)
        .motion(Motion.fade, value: introSeen)
        .onAppear(perform: start)
        .onChange(of: browser?.url) { _, _ in failure = nil }
        // Following stops, sending nothing, when the person leaves the tab or the app.
        .onChange(of: active) { _, now in if !now { following?.stop() } }
        .onChange(of: scenePhase) { _, phase in if phase == .background { following?.stop() } }
        // Settings signed this site out of Cetchup: start over at its sign-in page.
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
        // `-webFixture <file>` picks another one, like ig-thread-fixture-virtual.
        if UserDefaults.standard.bool(forKey: "Ketchup\(source.name)Fixture"),
           let fixture = source.fixtures.first(where: { $0.file == UserDefaults.standard.string(forKey: "webFixture") })
               ?? source.fixtures.first {
            b.open(fixture)
            Task { await debugRuns(b) }
            return
        }
        #endif
        b.openStart()
    }

    // MARK: Catch me up

    /// The page's one ketchup thing: a small circle with the drop, so it
    /// covers little of the chat. It picks how many of the newest messages
    /// to read, or reads along while the person scrolls.
    private func catchUpButton(_ browser: WebChatBrowser) -> some View {
        Menu {
            Section("Catch me up on the") {
                ForEach(Self.windows, id: \.self) { n in
                    Button("Last \(n) messages") { Task { await catchUp(browser, last: n) } }
                }
            }
            Section {
                Button("Until I stop scrolling") { Task { await follow(browser) } }
            }
        } label: {
            CatchUpCircle(reading: reading)
        }
        .menuOrder(.fixed)
        .disabled(reading)
        .accessibilityLabel(reading ? "Reading the chat" : "Catch me up")
        .accessibilityHint("Pick how many of the newest messages to read, or read as you scroll")
    }

    private func run(_ pick: Pick, _ browser: WebChatBrowser) async {
        switch pick {
        case .last(let n): await catchUp(browser, last: n)
        case .untilStop: await follow(browser)
        }
    }

    private func catchUp(_ browser: WebChatBrowser, last: Int) async {
        guard !reading, following == nil else { return }
        reading = true
        failure = nil
        defer { reading = false }
        do {
            let thread = try await browser.readThread(readerName: readerName, last: last)
            #if DEBUG
            WebReadCheck.compare(thread, fixture: browser.fixture, last: last)
            #endif
            session = WebCatchUp(thread: thread, readerName: readerName)
        } catch {
            failure = Failure(message: WebChatError.message(for: error), pick: .last(last))
        }
    }

    /// "Until I stop scrolling": Cetchup never scrolls; the panel counts
    /// what's been read while the person does. When they stop, it's the
    /// same catch-up as a Last N read. Stopped (Stop, or they left), it
    /// sends nothing and keeps nothing.
    private func follow(_ browser: WebChatBrowser) async {
        guard !reading, following == nil else { return }
        failure = nil
        let follow = WebFollow()
        #if DEBUG
        follow.holds = UserDefaults.standard.bool(forKey: "followHold")
        #endif
        following = follow
        defer { following = nil }
        do {
            guard let thread = try await browser.follow(follow, readerName: readerName) else { return }
            #if DEBUG
            WebReadCheck.compare(thread, fixture: browser.fixture, last: nil)
            #endif
            session = WebCatchUp(thread: thread, readerName: readerName)
        } catch {
            failure = Failure(message: WebChatError.message(for: error), pick: .untilStop)
        }
    }

    #if DEBUG
    /// Offline checks on a test thread, from launch arguments: `-readTest 10`
    /// reads the last 10; `-followTest YES` (or moves like "up 8, down 2, up
    /// 120") follows while a pretend person scrolls the test page;
    /// `-followAuto YES` just starts following (the web-following preview).
    private func debugRuns(_ browser: WebChatBrowser) async {
        let defaults = UserDefaults.standard
        let last = defaults.integer(forKey: "readTest"), test = defaults.string(forKey: "followTest")
        guard last > 0 || test != nil || defaults.bool(forKey: "followAuto") else { return }
        await WebReadCheck.loaded(browser)
        if last > 0 {
            await catchUp(browser, last: last)
        } else {
            if let test { Task { await WebReadCheck.person(browser, moves: WebReadCheck.moves(test)) } }
            await follow(browser)
        }
    }
    #endif

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

/// "Until I stop scrolling" while it reads: paper over the bottom of the
/// page with the count so far and the two ways out. It takes touches only on
/// itself, so the chat around it still scrolls. At the biggest text sizes
/// it stops growing, so it can't cover the chat it's reading.
private struct FollowingPanel: View {
    let follow: WebFollow

    @ScaledMetric(relativeTo: .headline) private var drop: CGFloat = 22

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // The count beside the title, or under it when that doesn't fit (big text, small phones).
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 10) {
                    mark
                    heading
                    Spacer(minLength: 8)
                    count
                }
                HStack(alignment: .top, spacing: 10) {
                    mark
                    VStack(alignment: .leading, spacing: 6) {
                        heading
                        count
                    }
                }
            }
            Text("Scroll up through the chat. Cetchup reads as you go and catches you up when you stop.")
                .font(.subheadline)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Catch me up now", action: follow.catchUpNow)
                    .buttonStyle(.ketchup(.compact))
                Button("Stop", action: follow.stop)
                    .buttonStyle(.outline(.compact))
            }
        }
        .paperCard(padding: 16)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    private var mark: some View {
        KetchupDrop()
            .fill(Theme.ketchup)
            .frame(width: drop, height: drop)
            .accessibilityHidden(true)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 2) {
            Kicker("Until I stop scrolling")
            Text("Reading the chat")
                .font(.serif(.headline))
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var count: some View {
        Text(follow.found == 1 ? "1 message" : "\(follow.found.formatted()) messages")
            .font(.mono(.footnote))
            .foregroundStyle(Theme.ink)
            .monospacedDigit()
            .contentTransition(.numericText(value: Double(follow.found)))
            .motion(Motion.snappy, value: follow.found)
            .accessibilityAddTraits(.updatesFrequently)
    }
}

/// The slim bar over the site: its name in New York, and the page's own
/// buttons on the right.
struct WebChatBar<Trailing: View>: View {
    let title: String
    var close: (() -> Void)? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 6) {
            Text(verbatim: title)
                .font(.serif(.title3))
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
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
                    Text("Catch up on your \(source.name) chats")
                        .font(.serif(.title))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 14) {
                        point("person.badge.key", "Sign in on \(source.name)'s own page. Cetchup never sees your password.")
                        point("hand.tap", "Open a chat, tap the ketchup drop, and pick the last 10, 30, 80 or 120 messages, or let it read as you scroll. Cetchup reads only that chat, only when you tap.")
                        point("text.bubble", "Those messages, your friends' too, go to \(Theme.modelName) to sum up. The catch-up stays on this phone until you delete it, never on Cetchup's server.")
                        if let note = source.note {
                            point("plus.magnifyingglass", note)
                        }
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
