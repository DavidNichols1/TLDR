//
//  HomeTabs.swift
//  Ketchup
//
//  The signed-in home: Chats, Instagram, Snapchat and You, with a tab bar
//  along the bottom. Every tab keeps its state when you switch. A tab is
//  built the first time you open it and then stays, hidden while another
//  shows, so a web page loads once and keeps its sign-in, and nothing loses
//  its place. The app comes back to the tab you were on last.
//
//  The bar is paper we draw, not the system's glass: cream, a hairline, ink,
//  and a mustard mark under the tab you're on. It steps aside while a chat
//  is open, so the chat's input bar has the bottom of the screen.
//

import SwiftUI

/// A tab of the home.
enum HomeTab: Hashable, Identifiable {
    case chats
    /// A chat app's own website, with Catch me up for the open thread (WebChat/).
    case web(WebChatSource)
    /// Your profile: your people, Invite friends, Blocked people and Settings (People/YouView.swift).
    case you

    /// The tabs, left to right. Another chat app is one more `.web(…)` here.
    static let all: [HomeTab] = [.chats, .web(.instagram), .web(.snapchat), .you]

    /// What `home.page` remembers.
    var id: String {
        switch self {
        case .chats: "chats"
        case .web(let source): source.id
        case .you: "you"
        }
    }

    var title: String {
        switch self {
        case .chats: "Chats"
        case .web(let source): source.name
        case .you: "You"
        }
    }
}

// MARK: - Tabs

/// What the tabs share with their pages.
@Observable
final class HomeTabsState {
    /// A chat is open on the Chats tab: the bar steps aside, so the chat's
    /// input bar has the bottom of the screen. ChatsListView sets it.
    var locked = false
    /// The bar's height above the home indicator, so a page can keep its
    /// last row clear of it.
    var barHeight: CGFloat = 56
}

struct HomeTabs: View {
    @AppStorage("home.page") private var saved = HomeTab.chats.id
    @State private var selected: HomeTab
    /// Tabs built so far: Chats, the first tab, and each tab the first time
    /// it's opened. A built tab stays.
    @State private var built: Set<HomeTab>
    @State private var tabs = HomeTabsState()
    @Environment(AppModel.self) private var app

    private let remembers: Bool

    init() {
        let last = UserDefaults.standard.string(forKey: "home.page")
        self.init(start: HomeTab.all.first { $0.id == last } ?? .chats, remembers: true)
    }

    #if DEBUG
    /// Offline previews: opens on `tab` and doesn't remember it.
    init(previewing tab: HomeTab) {
        self.init(start: tab, remembers: false)
    }
    #endif

    private init(start: HomeTab, remembers: Bool) {
        _selected = State(initialValue: start)
        _built = State(initialValue: [.chats, start])
        self.remembers = remembers
    }

    var body: some View {
        ZStack {
            ForEach(HomeTab.all) { tab in
                if built.contains(tab) {
                    page(tab, active: tab == selected)
                        .opacity(tab == selected ? 1 : 0)
                        .allowsHitTesting(tab == selected)
                        .accessibilityHidden(tab != selected)
                }
            }
        }
        .overlay(alignment: .bottom) {
            HomeTabBar(selected: selected, select: select)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { tabs.barHeight = $0 }
                .opacity(tabs.locked ? 0 : 1)
                .allowsHitTesting(!tabs.locked)
                .accessibilityHidden(tabs.locked)
                .motion(Motion.fade, value: tabs.locked)
        }
        // The keyboard covers the bar instead of lifting it, and a web page
        // keeps its size under it, as in Safari: WebKit moves the page
        // itself. Chats and You are their own roots and make room for the
        // keyboard themselves.
        .ignoresSafeArea(.keyboard)
        .background(Theme.cream)
        .environment(tabs)
    }

    /// Chats and You are each their own SwiftUI root, full screen, so a
    /// chat's input bar meets the keyboard the way it does on a whole screen.
    /// The web pages stay plain views between the status bar and the tab
    /// bar: a web view handles the keyboard itself, and as a root it did so
    /// twice and went blank (the pager, Nov 3, 2026).
    @ViewBuilder
    private func page(_ tab: HomeTab, active: Bool) -> some View {
        switch tab {
        case .chats:
            // The inbox keeps its last row clear of the bar itself
            // (ChatsListView), so an open chat gets the whole screen.
            HostedPage(content: rooted(ChatsListView()), active: active)
                .ignoresSafeArea()
        case .you:
            // Every page pushed here ends above the bar.
            HostedPage(content: rooted(YouView()), active: active, bottomInset: tabs.barHeight)
                .ignoresSafeArea()
        case .web(let source):
            WebChatTab(source: source, active: active)
                .padding(.bottom, tabs.barHeight)
        }
    }

    /// A new root starts with a fresh environment, so it gets what
    /// KetchupApp's root sets, and the tabs' state.
    private func rooted<Content: View>(_ content: Content) -> some View {
        content
            .environment(app)
            .environment(tabs)
            .tint(Theme.ketchupText)
    }

    private func select(_ tab: HomeTab) {
        guard tab != selected else { return }
        // A keyboard left up on the old tab (a site's message box) goes with it.
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        if !built.contains(tab) { built.insert(tab) }
        selected = tab
        if remembers { saved = tab.id }
    }
}

/// A tab in its own hosting controller. Its content is set once: tabs take
/// no inputs, and what they show comes from the observable models they're
/// given. A hidden tab takes no touches and VoiceOver skips it.
private struct HostedPage<Content: View>: UIViewControllerRepresentable {
    let content: Content
    var active: Bool
    /// Room for the tab bar at the bottom, as safe area: the page's scroll
    /// views end above the bar, and a keyboard takes its place rather than
    /// stacking on it.
    var bottomInset: CGFloat = 0

    func makeUIViewController(context: Context) -> UIHostingController<Content> {
        let host = UIHostingController(rootView: content)
        host.view.backgroundColor = .clear
        apply(to: host)
        return host
    }

    func updateUIViewController(_ host: UIHostingController<Content>, context: Context) {
        apply(to: host)
    }

    private func apply(to host: UIHostingController<Content>) {
        if host.additionalSafeAreaInsets.bottom != bottomInset {
            host.additionalSafeAreaInsets.bottom = bottomInset
        }
        host.view.isUserInteractionEnabled = active
        host.view.accessibilityElementsHidden = !active
    }
}

// MARK: - Bar

/// The tab bar: cream paper under a hairline, ink for the tab you're on and
/// inkSoft for the rest, and a mustard mark under its name that slides over
/// as you switch (a fade with Reduce Motion). Like a system bar it stops
/// growing at Extra Extra Large text, and a long press shows a tab big
/// (Large Content Viewer).
private struct HomeTabBar: View {
    let selected: HomeTab
    let select: (HomeTab) -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var mark

    /// Everything waiting in your chats, as on the inbox.
    private var unread: Int { app.chats.reduce(0) { $0 + $1.unreadCount } }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(HomeTab.all) { tab in
                item(tab)
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 3)
        .animation(reduceMotion ? Motion.fade : Motion.snappy, value: selected)
        .background { Theme.cream.ignoresSafeArea() }
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.rule).frame(height: 1)
        }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isTabBar)
    }

    private func item(_ tab: HomeTab) -> some View {
        let on = tab == selected
        let count = tab == .chats ? unread : 0
        return Button { select(tab) } label: {
            VStack(spacing: 2) {
                HomeTabIcon(tab: tab, on: on, unread: count)
                Text(tab.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(on ? Theme.ink : Theme.inkSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 3)
                    .background(alignment: .bottom) {
                        if on { markStroke }
                    }
            }
            // Room under the name for the mark.
            .padding(.top, 3)
            .padding(.bottom, 7)
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(tab.title)
        .accessibilityValue(count == 0 ? "" : count == 1 ? "1 new message" : "\(count) new messages")
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityShowsLargeContentViewer {
            Label { Text(tab.title) } icon: { HomeTabIcon(tab: tab, on: on) }
        }
    }

    /// The mustard stroke under the name of the tab you're on.
    @ViewBuilder
    private var markStroke: some View {
        let stroke = MarkerStroke()
            .fill(Theme.mustard)
            .frame(height: 5)
            .offset(y: 6)
            .accessibilityHidden(true)
        if reduceMotion {
            stroke.transition(.opacity)
        } else {
            stroke.matchedGeometryEffect(id: "mark", in: mark)
        }
    }
}

/// A tab's picture, filled and ink for the tab you're on, outlined and
/// inkSoft for the rest: SF Symbols for Chats and Instagram, a ghost drawn
/// here for Snapchat (SF Symbols has none), and your own photo for You (your
/// initials until there is one). Chats carries a mustard count of what's
/// unread, like the inbox's badges.
private struct HomeTabIcon: View {
    let tab: HomeTab
    let on: Bool
    var unread = 0

    /// Optional: the Large Content Viewer draws this outside the bar.
    @Environment(AppModel.self) private var app: AppModel?
    @ScaledMetric(relativeTo: .title3) private var side: CGFloat = 28

    var body: some View {
        icon
            .foregroundStyle(on ? Theme.ink : Theme.inkSoft)
            .frame(width: side * 1.4, height: side)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var icon: some View {
        switch tab {
        case .chats:
            symbol("bubble.left.and.bubble.right")
                // The badge's left edge 7 pt in from the glyph's right, its
                // middle on the glyph's top, the way iOS badges sit.
                .alignmentGuide(.badgeX) { $0[.trailing] - 7 }
                .alignmentGuide(.badgeY) { $0[.top] + 3 }
                .overlay(alignment: Alignment(horizontal: .badgeX, vertical: .badgeY)) { badge }
        case .web(let source):
            if source.id == WebChatSource.snapchat.id {
                ghost
            } else {
                symbol(source.id == WebChatSource.instagram.id ? "camera" : "globe")
            }
        case .you:
            if let me = app?.me {
                photo(of: me)
            } else {
                symbol("person.crop.circle")
            }
        }
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .symbolVariant(on ? .fill : .none)
            .font(.system(size: side * 0.72, weight: .medium))
    }

    private var ghost: some View {
        let size = side * 0.9
        return ZStack {
            if on {
                GhostShape(part: .whole).fill(style: FillStyle(eoFill: true))
            } else {
                GhostShape(part: .body).stroke(style: StrokeStyle(lineWidth: size * 0.085, lineJoin: .round))
                GhostShape(part: .eyes).fill()
            }
        }
        .frame(width: size, height: size)
    }

    /// Your photo in its rounded square; an ink ring around it for the tab you're on.
    private func photo(of me: Profile) -> some View {
        let size = side - 5
        return Avatar(name: me.displayName, path: me.avatarPath, size: size)
            .frame(width: side, height: side)
            .overlay {
                if on {
                    RoundedRectangle(cornerRadius: side * 0.3, style: .continuous)
                        .strokeBorder(Theme.ink, lineWidth: 1.5)
                }
            }
    }

    @ViewBuilder
    private var badge: some View {
        if unread > 0 {
            Text(unread > 999 ? "999+" : "\(unread)")
                .font(.mono(.caption2, weight: .bold))
                .foregroundStyle(Theme.onMustard)
                .padding(.horizontal, 4)
                .frame(minWidth: 16, minHeight: 16)
                .background(Theme.mustard, in: Capsule())
                .fixedSize()
                .alignmentGuide(.badgeX) { $0[.leading] }
                .alignmentGuide(.badgeY) { $0[VerticalAlignment.center] }
        }
    }
}

/// Where an unread badge meets its glyph.
private extension HorizontalAlignment {
    enum BadgeX: AlignmentID {
        static func defaultValue(in d: ViewDimensions) -> CGFloat { d[.trailing] }
    }
    static let badgeX = HorizontalAlignment(BadgeX.self)
}

private extension VerticalAlignment {
    enum BadgeY: AlignmentID {
        static func defaultValue(in d: ViewDimensions) -> CGFloat { d[.top] }
    }
    static let badgeY = VerticalAlignment(BadgeY.self)
}

/// Snapchat's tab: a little ghost, since SF Symbols has none. A dome on
/// straight sides with a hem of three scallops, and two eyes. Drawn in a
/// unit square with curves only, like KetchupDrop. `.whole` keeps the eyes
/// as their own subpaths, so an even-odd fill punches them out.
nonisolated private struct GhostShape: Shape {
    enum Part { case whole, body, eyes }
    let part: Part

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let x0 = rect.midX - side / 2, y0 = rect.midY - side / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: x0 + x * side, y: y0 + y * side)
        }
        var path = Path()
        if part != .eyes {
            let left: CGFloat = 0.19, right: CGFloat = 0.81, radius: CGFloat = 0.31
            let shoulder: CGFloat = 0.43, hem: CGFloat = 0.81
            // A quarter circle's control length.
            let k = radius * 0.5523
            path.move(to: p(left, hem))
            path.addLine(to: p(left, shoulder))
            path.addCurve(to: p(0.5, shoulder - radius), control1: p(left, shoulder - k), control2: p(0.5 - k, shoulder - radius))
            path.addCurve(to: p(right, shoulder), control1: p(0.5 + k, shoulder - radius), control2: p(right, shoulder - k))
            path.addLine(to: p(right, hem))
            // The hem, right to left: three scallops hanging down.
            let width = (right - left) / 3
            for i in 0..<3 {
                let from = right - CGFloat(i) * width
                let to = from - width
                path.addQuadCurve(to: p(to, hem), control: p((from + to) / 2, hem + 0.16))
            }
            path.closeSubpath()
        }
        if part != .body {
            let eye = CGSize(width: 0.085 * side, height: 0.12 * side)
            path.addEllipse(in: CGRect(origin: p(0.4 - 0.0425, 0.44 - 0.06), size: eye))
            path.addEllipse(in: CGRect(origin: p(0.6 - 0.0425, 0.44 - 0.06), size: eye))
        }
        return path
    }
}

