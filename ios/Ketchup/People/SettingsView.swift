//
//  SettingsView.swift
//  Ketchup
//
//  Settings, from the inbox's top-left button: who you are (your name,
//  which you can change, and the email you sign in with), your people and
//  inviting friends, blocked people, the web chats' sign-ins, signing out,
//  deleting your account, and about. Its pages are in AccountPages.swift,
//  PeopleView.swift, InviteView.swift and BlockedPeopleView.swift.
//
//  Two sections hold other features' rows: profilePhotoSlot (Photos/) and
//  savedCatchUpsSlot under "On this iPhone" (Saved/). A section whose rows
//  are all empty doesn't show.
//

import SwiftUI

struct SettingsView: View {
    /// Closes the sheet, then signs out (ChatsListView runs it once the
    /// sheet is gone).
    let close: (SettingsExit) -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var confirmSignOut = false
    /// A delete is on its way: Done and swipe-down wait for it.
    @State private var deleting = false
    @State private var choosingPhoto = false
    @State private var photoProblem: String?

    @ScaledMetric(relativeTo: .largeTitle) private var monogramSize: CGFloat = 56

    /// "You" until the profile has loaded.
    private var name: String { app.me?.displayName ?? "You" }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 30) {
                        header
                        you
                        people.id("people")
                        privacy.id("privacy")
                        WebChatSignOutSection().id("web")
                        onThisPhone.id("phone")
                        account.id("account")
                        about.id("about")
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 36)
                }
                #if DEBUG
                // `-section web`, `account` or `about` scrolls a preview there.
                .onAppear {
                    if let section = PreviewData.section { proxy.scrollTo(section, anchor: .top) }
                }
                #endif
            }
            .background(Theme.cream)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // The big header says whose settings these are; the bar keeps just Done.
                ToolbarItem(placement: .principal) {
                    Color.clear.frame(width: 1, height: 1).accessibilityHidden(true)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .disabled(deleting)
                }
            }
            .confirmationDialog("Sign out of Ketchup?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { close(.signOut) }
                Button("Cancel", role: .cancel) {}
            } message: {
                if let email = app.accountEmail {
                    Text("Ketchup also forgets your Instagram and Snapchat sign-ins on this iPhone. To get back in, you'll sign in with a code sent to \(email).")
                }
            }
            // A new name that didn't go through (AppModel.renameNow).
            .alert("Didn't go through", isPresented: Binding(get: { app.problem != nil },
                                                           set: { if !$0 { app.problem = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(app.problem ?? "")
            }
        }
        .interactiveDismissDisabled(deleting)
        .profilePhotoPicker(isPresented: $choosingPhoto)
        .alert("Couldn't remove your photo", isPresented: Binding(get: { photoProblem != nil },
                                                                  set: { if !$0 { photoProblem = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(photoProblem ?? "")
        }
        .presentationBackground(Theme.cream)
    }

    // MARK: You

    /// "Settings" over your name in New York, the email you sign in with,
    /// and your monogram.
    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Kicker("Settings")
                Text(name)
                    .font(.serif(.largeTitle))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .accessibilityAddTraits(.isHeader)
                if let email = app.accountEmail {
                    Text(email)
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSoft)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .accessibilityLabel("Signed in as \(email)")
                }
            }
            Spacer(minLength: 0)
            Avatar(name: app.me?.displayName ?? "?", path: app.me?.avatarPath, size: monogramSize)
        }
        .padding(.top, 6)
    }

    private var you: some View {
        SettingsSection("You", footer: "Friends see your name and photo in your chats, and \(Theme.modelName) uses your name in catch-ups.") {
            NavigationLink {
                EditNameView()
            } label: {
                SettingsRow("Change your name", systemImage: "pencil", chevron: true)
            }
            .buttonStyle(.pressable)
            profilePhotoSlot
        }
    }

    /// Your profile photo: pick and frame a new one (Photos/ProfilePhotos.swift),
    /// or go back to your monogram.
    @ViewBuilder private var profilePhotoSlot: some View {
        Button { choosingPhoto = true } label: {
            SettingsRow(app.me?.avatarPath == nil ? "Add a photo" : "Change your photo", systemImage: "photo")
        }
        .buttonStyle(.pressable)
        if app.me?.avatarPath != nil {
            Button { Task { await removePhoto() } } label: {
                SettingsRow("Remove your photo", systemImage: "person.crop.square")
            }
            .buttonStyle(.pressable)
        }
    }

    private func removePhoto() async {
        do {
            try await ProfilePhotos.remove(app: app)
        } catch {
            photoProblem = error.localizedDescription
        }
    }

    // MARK: People

    private var people: some View {
        SettingsSection("People") {
            NavigationLink {
                PeopleView()
            } label: {
                SettingsRow("Your people", systemImage: "person.2", value: peopleCount, chevron: true)
            }
            .buttonStyle(.pressable)
            NavigationLink {
                InviteView()
            } label: {
                SettingsRow("Invite friends", systemImage: "paperplane", chevron: true)
            }
            .buttonStyle(.pressable)
        }
        .task { await PeopleStore.shared.loadContacts() }
    }

    /// "None" or how many, once the list has loaded.
    private var peopleCount: String? {
        let store = PeopleStore.shared
        guard store.contactsLoaded else { return nil }
        return store.contacts.isEmpty ? "None" : "\(store.contacts.count)"
    }

    // MARK: Privacy

    private var privacy: some View {
        SettingsSection("Privacy") {
            NavigationLink {
                BlockedPeopleView()
            } label: {
                SettingsRow("Blocked people", systemImage: "hand.raised", value: blockedCount, chevron: true)
            }
            .buttonStyle(.pressable)
        }
        .task { await PeopleStore.shared.load() }
    }

    /// "None" or how many, once the list has loaded.
    private var blockedCount: String? {
        let store = PeopleStore.shared
        guard store.loaded else { return nil }
        return store.blocked.isEmpty ? "None" : "\(store.blocked.count)"
    }

    // MARK: On this iPhone

    private var onThisPhone: some View {
        SettingsSection("On this iPhone") {
            savedCatchUpsSlot
        }
    }

    /// "Saved catch-ups" and "Clear cache" (Saved/SavedCatchUps.swift).
    @ViewBuilder private var savedCatchUpsSlot: some View {
        SavedCatchUpsRow()
        ClearCacheRow()
        #if DEBUG
        DedupeTestRow()
        #endif
    }

    // MARK: Account

    private var account: some View {
        SettingsSection("Account") {
            Button {
                confirmSignOut = true
            } label: {
                SettingsRow("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
            }
            .buttonStyle(.pressable)
            NavigationLink {
                DeleteAccountView(deleting: $deleting) { close(.accountDeleted) }
            } label: {
                SettingsRow("Delete account", systemImage: "trash", destructive: true, chevron: true)
            }
            .buttonStyle(.pressable)
        }
    }

    // MARK: About

    /// The colophon: the drop and the name, the version, Muse Spark's
    /// byline, and where Ketchup was made.
    private var about: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("About")
            VStack(spacing: 10) {
                KetchupDrop()
                    .fill(Theme.ketchup)
                    .frame(width: 30, height: 30)
                    .rotationEffect(.degrees(-8))
                    .accessibilityHidden(true)
                Wordmark(size: 30)
                Kicker("Version \(Self.version)")
                    .padding(.top, 2)
                MuseByline(verb: "Read by")
                Text("Built for the Meta Global AI Developer Hackathon, November 2026.")
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .paperCard(padding: 20)
            .accessibilityElement(children: .combine)
        }
    }

    /// "1.0 (1)": the version and build from Info.plist.
    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
}

// MARK: - Web chats

/// "Sign out of Instagram in Ketchup", and Snapchat. Each forgets what
/// that site saved in Ketchup's web views on this iPhone.
private struct WebChatSignOutSection: View {
    var body: some View {
        SettingsSection("Web chats", kicker: "Experimental",
                        footer: "Ketchup's browser forgets that site's sign-in and saved data on this iPhone, so you'll sign in on its page again. Your accounts aren't touched. Signing out of Ketchup forgets both.") {
            ForEach(WebChatSource.all) { source in
                WebChatSignOutRow(source: source)
            }
        }
    }
}

private struct WebChatSignOutRow: View {
    let source: WebChatSource

    private enum Status { case checking, saved, nothingSaved, working, done }

    @State private var status = Status.checking
    @State private var confirm = false

    var body: some View {
        Button {
            confirm = true
        } label: {
            SettingsRow("Sign out of \(source.name) in Ketchup", systemImage: "globe", detail: detail) {
                switch status {
                case .working:
                    ProgressView().tint(Theme.inkSoft)
                case .done:
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.pickle)
                        .accessibilityHidden(true)
                case .checking, .saved, .nothingSaved:
                    EmptyView()
                }
            }
        }
        .buttonStyle(.pressable)
        // Usable while the check runs (forgetting nothing is harmless); the
        // first check after launch can take a few seconds while WebKit starts.
        .disabled(status == .nothingSaved || status == .working || status == .done)
        .sensoryFeedback(.success, trigger: status) { _, now in now == .done }
        .task { status = await source.hasSavedData() ? .saved : .nothingSaved }
        .confirmationDialog("Sign out of \(source.name) in Ketchup?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Sign out of \(source.name)", role: .destructive) {
                Task { await forget() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Ketchup forgets \(source.name)'s sign-in and what its site saved on this iPhone. Your \(source.name) account isn't touched.")
        }
    }

    private var detail: String? {
        switch status {
        case .nothingSaved: "Nothing saved"
        case .done: "Signed out"
        case .checking, .saved, .working: nil
        }
    }

    private func forget() async {
        status = .working
        // Offline previews share the phone's real website data: leave it be.
        if !Previewing.isOn { await source.forgetSavedData() }
        status = .done
    }
}
