//
//  Terms.swift
//  Ketchup
//
//  Cetchup's Terms of Service and Privacy Policy (migration 0011). The
//  sign-in screen says "By continuing, you agree to Cetchup's Terms of
//  Service and Privacy Policy" (TermsLine), and every sign-in records it
//  with accept_terms. Someone already signed in with nothing on record, or
//  an agreement older than Config.termsVersion, gets TermsSheet once, full
//  screen, before the app. The links open in Safari inside the app.
//
//  The check never holds the app hostage: offline, or on a server without
//  0011, the app opens and the next launch asks again.
//

import SwiftUI
import SafariServices

// MARK: - State

@Observable
final class TermsStore {
    static let shared = TermsStore()

    enum Status: Equatable {
        /// Not known yet, or the server couldn't say: the app opens as usual.
        case unknown
        case agreed
        /// Nothing on record for this version: TermsSheet shows.
        case needed
    }

    private(set) var status = Status.unknown
    private(set) var saving = false
    /// Why Agree didn't go through, shown on the sheet over its button.
    private(set) var problem: String?
    private var user: UUID?

    var showsSheet: Bool { status == .needed }

    /// RootView, whenever who's signed in changes (launch, sign-in, sign-out).
    func signedIn(_ id: UUID?) async {
        guard id != user else { return }  // a sign-in here already settled it
        user = id
        status = .unknown
        problem = nil
        guard let id else { return }
        if let kept = kept(for: id), kept >= Config.termsVersion {
            status = .agreed
            return
        }
        await check(id)
    }

    /// Right after a sign-in (code or password): the sign-in screen said
    /// that continuing agrees, so record it now. Agreed at once, before the
    /// call, so RootView's own check can't flash the sheet meanwhile. If it
    /// can't be recorded, the usual check decides.
    func agreedAtSignIn() async {
        guard let id = Supabase.shared.userId else { return }
        user = id
        status = .agreed
        problem = nil
        do {
            try await record(id)
        } catch {
            guard user == id else { return }
            status = .unknown
            await check(id)
        }
    }

    /// The sheet's Agree. A failure stays on the sheet, with the button there to try again.
    func agree() async {
        guard let id = user ?? Supabase.shared.userId ?? previewUser, !saving else { return }
        saving = true
        problem = nil
        defer { saving = false }
        do {
            try await record(id)
            guard user == nil || user == id else { return }
            status = .agreed
        } catch {
            problem = "Couldn't save that. Check your connection and try again."
        }
    }

    // MARK: Server

    private func check(_ id: UUID) async {
        do {
            let data = try await Supabase.shared.rest("GET", "/rest/v1/terms_acceptances",
                                                      query: [URLQueryItem(name: "select", value: "version")])
            struct Row: Decodable { let version: String }
            let version = try JSONDecoder().decode([Row].self, from: data).first?.version
            guard user == id, status != .agreed else { return }
            if let version, version >= Config.termsVersion {
                keep(version, for: id)
                status = .agreed
            } else {
                status = .needed
            }
        } catch {
            // Offline, or a server without 0011 yet: let them in this time.
            guard user == id, status != .agreed else { return }
            status = .unknown
        }
    }

    private func record(_ id: UUID) async throws {
        _ = try await Supabase.shared.rpc("accept_terms", ["p_version": Config.termsVersion])
        keep(Config.termsVersion, for: id)
    }

    // MARK: Kept on the phone

    /// The version this person last agreed to, once the server has it, so
    /// later launches ask nothing.
    private func kept(for id: UUID) -> String? {
        UserDefaults.standard.string(forKey: key(id))
    }

    private func keep(_ version: String, for id: UUID) {
        guard previewUser == nil else { return }
        UserDefaults.standard.set(version, forKey: key(id))
    }

    private func key(_ id: UUID) -> String { "termsAccepted-\(id.uuidString.lowercased())" }

    /// Offline previews: the sheet's made-up person.
    private var previewUser: UUID? {
        #if DEBUG
        if PreviewData.isActive { return PreviewData.me }
        #endif
        return nil
    }

    /// "Updated November 4, 2026", from the version.
    static var updatedLine: String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(identifier: "UTC")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: Config.termsVersion) else { return "Version \(Config.termsVersion)" }
        var style = Date.FormatStyle(date: .long, time: .omitted)
        style.timeZone = TimeZone(identifier: "UTC") ?? .current
        return "Updated \(date.formatted(style))"
    }
}

// MARK: - The line on the sign-in screen

/// "By continuing, you agree to Cetchup's Terms of Service and Privacy
/// Policy." Both names are links that open in Safari inside the app. It
/// wraps at any text size; VoiceOver reaches the links through the rotor or
/// the two actions.
struct TermsLine: View {
    @State private var page: WebPage?

    var body: some View {
        Text(Self.line)
            .font(.footnote)
            .foregroundStyle(Theme.inkSoft)
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.openURL, OpenURLAction { url in
                page = WebPage(url: url)
                return .handled
            })
            .accessibilityAction(named: "Terms of Service") { page = WebPage(url: Config.termsURL) }
            .accessibilityAction(named: "Privacy Policy") { page = WebPage(url: Config.privacyURL) }
            .webPage($page)
    }

    static var line: AttributedString {
        var line = AttributedString("By continuing, you agree to Cetchup's ")
        line += link("Terms of Service", Config.termsURL)
        line += AttributedString(" and ")
        line += link("Privacy Policy", Config.privacyURL)
        line += AttributedString(".")
        return line
    }

    private static func link(_ text: String, _ url: URL) -> AttributedString {
        var part = AttributedString(text)
        part.link = url
        part.underlineStyle = .single
        part.font = .footnote.weight(.semibold)
        part.foregroundColor = Theme.ketchupText
        return part
    }
}

// MARK: - The one-time sheet

/// Full screen, before the app, for someone signed in who hasn't agreed to
/// this version: the two links, Agree (accept_terms) and Sign out.
struct TermsSheet: View {
    @Environment(AppModel.self) private var app
    @State private var page: WebPage?
    @ScaledMetric(relativeTo: .largeTitle) private var dropSize: CGFloat = 40

    private var store: TermsStore { TermsStore.shared }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                Text("Please read them, then tap Agree to keep using Cetchup.")
                    .font(.body)
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                documents
                VStack(alignment: .leading, spacing: 12) {
                    if let problem = store.problem {
                        FormError(text: problem)
                    }
                    Button {
                        Task { await store.agree() }
                    } label: {
                        ZStack {
                            Text("Agree").opacity(store.saving ? 0 : 1)
                            if store.saving { ProgressView().tint(Theme.onKetchup) }
                        }
                    }
                    .buttonStyle(.ketchup)
                    .disabled(store.saving)
                    Button("Sign out") {
                        Task { await app.signOut() }
                    }
                    .buttonStyle(.outline)
                    .disabled(store.saving)
                }
                Text(TermsStore.updatedLine)
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSoft)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 32)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.cream)
        .webPage($page)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("Cetchup's Terms and Privacy Policy")
                .font(.serif(.largeTitle))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            KetchupDrop()
                .fill(Theme.ketchup)
                .frame(width: dropSize, height: dropSize)
                .rotationEffect(.degrees(-8))
                .accessibilityHidden(true)
        }
    }

    private var documents: some View {
        VStack(alignment: .leading, spacing: 0) {
            document("Terms of Service", systemImage: "doc.text", url: Config.termsURL)
            SettingsHairline()
            document("Privacy Policy", systemImage: "hand.raised", url: Config.privacyURL)
        }
        .paperCard(padding: 0)
    }

    private func document(_ title: String, systemImage: String, url: URL) -> some View {
        Button {
            page = WebPage(url: url)
        } label: {
            SettingsRow(title, systemImage: systemImage) {
                Image(systemName: "arrow.up.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.inkFaint)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.pressable)
        .accessibilityHint("Opens it in Safari")
    }
}

// MARK: - Safari

/// A page to show in Safari inside the app.
struct WebPage: Identifiable {
    let url: URL
    var id: URL { url }
}

extension View {
    /// Shows `page` in SFSafariViewController while it's set.
    func webPage(_ page: Binding<WebPage?>) -> some View {
        sheet(item: page) { page in
            SafariView(url: page.url).ignoresSafeArea()
        }
    }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.dismissButtonStyle = .done
        controller.preferredControlTintColor = UIColor(Theme.ketchupText)
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
