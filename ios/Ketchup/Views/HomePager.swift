//
//  HomePager.swift
//  Ketchup
//
//  The signed-in home: Chats, Instagram and Snapchat side by side. Swipe
//  between them, or tap a name in the switcher at the top. Chats is the
//  first page, and the app comes back to the page you were on last.
//
//  Paging uses the system scroll physics. While a chat is open the pages
//  stay put, so the chat's own back swipe works, and the switcher steps
//  aside for the chat's title.
//

import SwiftUI

/// The home's pages, left to right.
enum HomePage: String, CaseIterable, Identifiable {
    case chats, instagram, snapchat

    var id: Self { self }

    var title: String {
        switch self {
        case .chats: "Chats"
        case .instagram: "Instagram"
        case .snapchat: "Snapchat"
        }
    }
}

// MARK: - Page adapter

extension HomePage {
    /// What each page shows: the one place the pager hosts other screens.
    /// The Instagram session is turning its screen into `WebChatTab(source:)`;
    /// at merge the Instagram and Snapchat lines become
    /// `WebChatTab(source: .instagram)` and `WebChatTab(source: .snapchat)`.
    @ViewBuilder
    var content: some View {
        switch self {
        case .chats: ChatsListView()
        case .instagram: InstagramCatchUpScreen()
        case .snapchat: SnapchatComingSoon()
        }
    }
}

// MARK: - Pager

/// What a page tells the pager. The Chats page sets it.
@Observable
final class HomePagerState {
    /// A pushed screen (an open chat) is showing: no paging, no switcher.
    var locked = false
}

struct HomePager: View {
    @AppStorage("home.page") private var saved = HomePage.chats
    @State private var page: HomePage?
    /// Where the pages are: 0 is Chats, 1 Instagram, 2 Snapchat, fractions mid-swipe.
    @State private var position: CGFloat
    /// Pages built so far. A web page is built the first time you head its
    /// way, then kept, so it doesn't reload every time you swipe past.
    @State private var built: Set<HomePage>
    @State private var phase = ScrollPhase.idle
    @State private var statusBar: CGFloat = 0
    @State private var pager = HomePagerState()
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let start: HomePage
    private let remembers: Bool

    /// A top bar's row of buttons, under the status bar. The switcher sits
    /// in the Chats page's, between its buttons; the other pages leave the
    /// same row free above their own content.
    private static let barRow: CGFloat = 44

    init() {
        let last = UserDefaults.standard.string(forKey: "home.page").flatMap(HomePage.init) ?? .chats
        self.init(start: last, remembers: true)
    }

    #if DEBUG
    /// Offline previews: opens on `page` and doesn't remember it.
    init(previewing page: HomePage) {
        self.init(start: page, remembers: false)
    }
    #endif

    private init(start: HomePage, remembers: Bool) {
        _page = State(initialValue: start)
        _position = State(initialValue: CGFloat(start.index))
        _built = State(initialValue: [.chats, .snapchat, start])
        self.start = start
        self.remembers = remembers
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Full screen, so each page sits under the status bar and over the
            // home indicator and handles them itself. With the keyboard up the
            // pages end at its top, and as their own roots (hosted(_:)) a
            // chat's input bar rides on it.
            GeometryReader { geo in
                pages(size: geo.size, belowBar: statusBar + Self.barRow)
            }
            .ignoresSafeArea(.container)
            // Just under the status bar, between the bar's two buttons.
            HomeSwitcher(position: position, select: select)
                .background { paperUnderSwitcher }
                .padding(.horizontal, 68)
                .frame(height: Self.barRow)
                .opacity(pager.locked ? 0 : 1)
                .allowsHitTesting(!pager.locked)
                .accessibilityHidden(pager.locked)
                .motion(Motion.fade, value: pager.locked)
        }
        // This stack stays out of the status bar, so its top is the status bar's bottom.
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { statusBar = $0 }
        .background(Theme.cream)
        .environment(pager)
    }

    /// Cream behind the names, fading out at both ends, so the Chats page's
    /// "+" slips under the switcher as the page slides away instead of
    /// showing through it.
    private var paperUnderSwitcher: some View {
        Theme.cream
            .padding(.horizontal, -12)
            .mask {
                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.1),
                                       .init(color: .black, location: 0.9), .init(color: .clear, location: 1)],
                               startPoint: .leading, endPoint: .trailing)
                    .padding(.horizontal, -12)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func pages(size: CGSize, belowBar: CGFloat) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                ForEach(HomePage.allCases) { page in
                    pageView(page, belowBar: belowBar)
                        .frame(width: size.width, height: size.height)
                        .id(page)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        // Opens on the starting page (the scroll position alone starts at Chats).
        .defaultScrollAnchor(UnitPoint(x: CGFloat(start.index) / CGFloat(HomePage.allCases.count - 1), y: 0.5),
                             for: .initialOffset)
        .scrollPosition(id: $page)
        .scrollDisabled(pager.locked)
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            geo.contentOffset.x / max(geo.containerSize.width, 1)
        } action: { _, new in
            position = new
            // Build the page a swipe is heading for, so it's there as it slides in.
            if phase == .interacting { buildNeighbors(of: new) }
        }
        .onScrollPhaseChange { _, new in phase = new }
        .onChange(of: page) { _, new in
            guard let new else { return }
            // A tap's scroll passes pages on its way; select() built the one it's going to.
            if phase != .animating { build(new) }
            if remembers { saved = new }
        }
    }

    /// Chats fills its page and has its own top bar. The other pages start
    /// under the switcher's row, on cream until they're built.
    @ViewBuilder
    private func pageView(_ page: HomePage, belowBar: CGFloat) -> some View {
        if page == .chats {
            hosted(page)
        } else {
            VStack(spacing: 0) {
                Color.clear.frame(height: belowBar)
                if built.contains(page) {
                    page.content
                } else {
                    Theme.cream
                }
            }
            .background(Theme.cream)
        }
    }

    /// Chats as its own SwiftUI root, so a chat's input bar meets the
    /// keyboard the way it does on a whole screen; straight inside the
    /// paging scroll view it stayed under the keyboard. The web pages stay
    /// plain views: a web view handles the keyboard itself, and as a root it
    /// did so twice and went blank. A new root starts with a fresh
    /// environment, so it gets what KetchupApp's root sets.
    private func hosted(_ page: HomePage) -> some View {
        HostedPage(content: page.content
            .environment(app)
            .environment(pager)
            .tint(Theme.ketchupText))
    }

    private func buildNeighbors(of position: CGFloat) {
        let last = CGFloat(HomePage.allCases.count - 1)
        let clamped = min(max(position, 0), last)
        for index in [clamped.rounded(.down), clamped.rounded(.up)] {
            build(HomePage.allCases[Int(index)])
        }
    }

    /// Only writes when it's new: this runs on every frame of a swipe.
    private func build(_ page: HomePage) {
        if !built.contains(page) { built.insert(page) }
    }

    private func select(_ target: HomePage) {
        guard target != page else { return }
        build(target)
        withAnimation(reduceMotion ? nil : Motion.settle) { page = target }
    }
}

private extension HomePage {
    var index: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

/// A page in its own hosting controller. Its content is set once: pages take
/// no inputs, and what they show comes from the observable models they're given.
private struct HostedPage<Content: View>: UIViewControllerRepresentable {
    let content: Content

    func makeUIViewController(context: Context) -> UIHostingController<Content> {
        let host = UIHostingController(rootView: content)
        host.view.backgroundColor = .clear
        return host
    }

    func updateUIViewController(_ host: UIHostingController<Content>, context: Context) {}
}

// MARK: - Switcher

/// Chats, Instagram and Snapchat across the top bar, with a mustard mark
/// under the page you're on. The mark slides along as the pages scroll.
private struct HomeSwitcher: View {
    /// 0 is Chats, 1 Instagram, 2 Snapchat; fractions mid-swipe.
    let position: CGFloat
    let select: (HomePage) -> Void

    @State private var labels: [HomePage: CGRect] = [:]

    private static let space = "home.switcher"

    /// The page nearest the middle of the screen.
    private var current: HomePage {
        let index = min(max(Int(position.rounded()), 0), HomePage.allCases.count - 1)
        return HomePage.allCases[index]
    }

    var body: some View {
        // A smaller size first if the bigger one won't fit between the bar's buttons.
        ViewThatFits(in: .horizontal) {
            row(.serif(.headline))
            row(.serif(.subheadline))
        }
        // Bar titles keep their size; the Large Content Viewer shows them big.
        .dynamicTypeSize(...DynamicTypeSize.large)
    }

    private func row(_ font: Font) -> some View {
        HStack(spacing: 2) {
            ForEach(HomePage.allCases) { page in
                Button { select(page) } label: {
                    Text(page.title)
                        .font(font)
                        .foregroundStyle(page == current ? Theme.ink : Theme.inkSoft)
                        .lineLimit(1)
                        .fixedSize()
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: {
                            labels[page] = $0
                        }
                        .padding(.horizontal, 8)
                        .frame(maxHeight: .infinity)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(page == current ? .isSelected : [])
                .accessibilityShowsLargeContentViewer()
            }
        }
        .background(alignment: .topLeading) { mark }
        .coordinateSpace(.named(Self.space))
    }

    /// The marker stroke under the current name; part way between two names mid-swipe.
    @ViewBuilder
    private var mark: some View {
        let pages = HomePage.allCases
        let clamped = min(max(position, 0), CGFloat(pages.count - 1))
        let lower = Int(clamped.rounded(.down))
        let upper = min(lower + 1, pages.count - 1)
        if let from = labels[pages[lower]], let to = labels[pages[upper]] {
            let t = clamped - CGFloat(lower)
            let x = from.minX + (to.minX - from.minX) * t
            let width = from.width + (to.width - from.width) * t
            MarkerStroke()
                .fill(Theme.mustard)
                .frame(width: width + 6, height: 7)
                .offset(x: x - 3, y: from.maxY)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Snapchat, for now

/// Until Snapchat's page lands: an order ticket for what's coming.
private struct SnapchatComingSoon: View {
    var body: some View {
        ScrollView {
            Ticket(notchAt: 0.74) {
                VStack(alignment: .leading, spacing: 6) {
                    Kicker("In the kitchen")
                    Text("Snapchat is on the way")
                        .font(.serif(.title2))
                        .foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text("Catching up on Snapchat chats isn't ready yet. Instagram is one page back.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } stub: {
                Stamp("Soon", color: Theme.inkSoft, dashed: true)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .defaultScrollAnchor(.center, for: .alignment)
        .background(Theme.cream)
    }
}
