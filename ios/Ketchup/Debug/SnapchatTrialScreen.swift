//
//  SnapchatTrialScreen.swift
//  Ketchup
//
//  DEBUG only, Nov 3, 2026: can Snapchat for Web reach its chats in a web
//  view on a phone without anything injected into its pages? Step 2 asks
//  WebKit for the desktop page with a desktop Safari user agent. Step 3 also
//  lays the page out 1280 pt wide and scales it down to fit, so the page
//  gets a genuinely wide window. Nothing runs in any page: the trail is the
//  web view's own URL as it changes (host and path, ids and queries left
//  out), and the page title only in the simulator, where nobody signs in.
//  `-screen web-snapchat-trial`, `-KetchupSnapchatStep 3` to start on step 3.
//

#if DEBUG
import SwiftUI
import WebKit

struct SnapchatTrialScreen: View {
    @State private var trial = SnapchatTrial(step: UserDefaults.standard.integer(forKey: "KetchupSnapchatStep") == 3 ? 3 : 2)

    var body: some View {
        VStack(spacing: 0) {
            WebChatBar(title: "Snapchat trial, step \(trial.step)") {
                Menu {
                    Button("Snapchat for Web", systemImage: "message") { trial.open(SnapchatTrial.web) }
                    Button("Sign-in page", systemImage: "person.badge.key") { trial.open(SnapchatTrial.signIn) }
                    Button("Reload", systemImage: "arrow.clockwise") { trial.webView.reload() }
                    Section("Start over as") {
                        Button("Step 2: desktop mode") { trial = SnapchatTrial(step: 2) }
                        Button("Step 3: desktop mode, 1280 pt wide") { trial = SnapchatTrial(step: 3) }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 40, height: 40)
                        .contentShape(.rect)
                }
            }
            SnapchatTrialWebView(webView: trial.webView, layoutWidth: trial.layoutWidth)
                .id(ObjectIdentifier(trial))
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(trial.trail.suffix(7).enumerated()), id: \.offset) { _, line in
                    Text(verbatim: line)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .font(.mono(.caption2))
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.card)
        }
        .background(Theme.cream)
        .onAppear { if trial.trail.count <= 1 { trial.open(SnapchatTrial.web) } }
    }
}

@Observable
final class SnapchatTrial {
    static let web = URL(string: "https://web.snapchat.com/")!
    static let signIn = URL(string: "https://accounts.snapchat.com/v2/login")!
    static let desktopAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/27.0 Safari/605.1.15"

    let step: Int
    @ObservationIgnored let webView: WKWebView
    @ObservationIgnored private let delegate = Delegate()
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    private(set) var trail: [String] = []

    var layoutWidth: CGFloat? { step == 3 ? 1280 : nil }

    init(step: Int) {
        self.step = step
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.defaultWebpagePreferences.preferredContentMode = .desktop
        webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = Self.desktopAgent
        webView.isInspectable = true
        webView.navigationDelegate = delegate
        webView.uiDelegate = delegate
        delegate.log = { [weak self] in self?.log($0) }
        observations = [
            webView.observe(\.url, options: [.new]) { [weak self] web, _ in
                MainActor.assumeIsolated { self?.log("url  " + Self.redact(web.url)) }
            },
        ]
        #if targetEnvironment(simulator)
        observations.append(webView.observe(\.title, options: [.new]) { [weak self] web, _ in
            MainActor.assumeIsolated { if let t = web.title, !t.isEmpty { self?.log("title \(t)") } }
        })
        #endif
        log("step \(step): desktop mode, Mac Safari agent" + (step == 3 ? ", laid out 1280 pt wide" : ""))
    }

    func open(_ url: URL) { webView.load(URLRequest(url: url)) }

    private func log(_ line: String) {
        let stamp = Date.now.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute().second())
        trail.append("\(stamp) \(line)")
        print("[snapchat-trial] \(line)")
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("snapchat-trail.txt")
        try? trail.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
    }

    /// Host and path only; any path piece that isn't a plain word becomes `:id`.
    static func redact(_ url: URL?) -> String {
        guard let url else { return "none" }
        guard let host = url.host else { return url.scheme ?? "?" }
        let parts = url.path.split(separator: "/").map { piece -> String in
            let s = String(piece)
            return s.range(of: "^([a-z][a-z-]{0,24}|v[0-9])$", options: .regularExpression) != nil ? s : ":id"
        }
        return host + "/" + parts.joined(separator: "/") + (url.query == nil ? "" : " +query")
    }

    final class Delegate: NSObject, WKNavigationDelegate, WKUIDelegate {
        var log: (String) -> Void = { _ in }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = action.request.url else { return .cancel }
            guard action.targetFrame?.isMainFrame != false else { return .allow }
            if url.scheme == "https" || url.scheme == "http" || url.scheme == "about" || url.scheme == "blob" {
                log("go   " + SnapchatTrial.redact(url))
                return .allow
            }
            log("app link \(url.scheme ?? "?"), cancelled")
            return .cancel
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            log("done " + SnapchatTrial.redact(webView.url))
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            log("fail \((error as NSError).code)")
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if action.request.url != nil { webView.load(action.request) }
            return nil
        }
    }
}

/// The trial's web view, laid out `layoutWidth` wide and scaled down to the
/// screen when that's set. A view transform, so touches still land right.
struct SnapchatTrialWebView: UIViewRepresentable {
    let webView: WKWebView
    let layoutWidth: CGFloat?

    func makeUIView(context: Context) -> Host { Host(webView: webView, layoutWidth: layoutWidth) }
    func updateUIView(_ uiView: Host, context: Context) {}

    final class Host: UIView {
        let webView: WKWebView
        let layoutWidth: CGFloat?

        init(webView: WKWebView, layoutWidth: CGFloat?) {
            self.webView = webView
            self.layoutWidth = layoutWidth
            super.init(frame: .zero)
            clipsToBounds = true
            addSubview(webView)
        }

        required init?(coder: NSCoder) { fatalError("not from a storyboard") }

        override func layoutSubviews() {
            super.layoutSubviews()
            guard let width = layoutWidth, bounds.width > 0, width > bounds.width else {
                webView.transform = .identity
                webView.frame = bounds
                return
            }
            let scale = bounds.width / width
            webView.bounds = CGRect(x: 0, y: 0, width: width, height: bounds.height / scale)
            webView.center = CGPoint(x: bounds.midX, y: bounds.midY)
            webView.transform = CGAffineTransform(scaleX: scale, y: scale)
        }
    }
}
#endif
