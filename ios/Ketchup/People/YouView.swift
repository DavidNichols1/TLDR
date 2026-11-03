//
//  YouView.swift
//  Ketchup
//
//  The You tab: your photo, name and email, your people (tap one for their
//  profile), Invite friends, Blocked people, and Settings, which opens as a
//  sheet. Built from Settings' and People's pieces (AccountHeader,
//  PeopleList, PrivacySection, SettingsSection), so it looks and acts like
//  them. Signing out waits for the Settings sheet to close (SettingsExit),
//  so it can't be left over sign-in.
//

import SwiftUI

struct YouView: View {
    @Environment(AppModel.self) private var app
    @State private var showSettings = false
    @State private var settingsExit: SettingsExit?

    private var store: PeopleStore { .shared }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    AccountHeader(kicker: chatsLine)
                    people
                    PrivacySection()
                    settings
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 36)
            }
            .background(Theme.cream)
            .refreshable { await store.loadContacts(force: true) }
            .navigationTitle("You")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // The big header says who this is; the bar stays empty.
                ToolbarItem(placement: .principal) {
                    Color.clear.frame(width: 1, height: 1).accessibilityHidden(true)
                }
            }
            .motion(value: store.contacts.map(\.id))
        }
        .task { await store.loadContacts(force: true) }
        // Signing out waits for the sheet to go, so it isn't left over sign-in.
        .sheet(isPresented: $showSettings, onDismiss: {
            guard let exit = settingsExit else { return }
            settingsExit = nil
            Task { await app.leave(exit) }
        }) {
            SettingsView { exit in
                if showSettings {
                    settingsExit = exit
                    showSettings = false
                } else {
                    // Already closed (a delete finished after the sheet
                    // went): nothing will dismiss it again, so leave now.
                    Task { await app.leave(exit) }
                }
            }
        }
        #if DEBUG
        // `-screen settings-sheet` opens Settings over this tab (PeoplePreviewScreen).
        .onAppear { if UserDefaults.standard.bool(forKey: "KetchupOpenSettings") { showSettings = true } }
        #endif
    }

    /// "In 4 chats", over your name.
    private var chatsLine: String {
        switch app.chats.count {
        case 0: "No chats yet"
        case 1: "In 1 chat"
        default: "In \(app.chats.count) chats"
        }
    }

    // MARK: Your people

    /// Everyone you've added, each with their photo and a way to their
    /// profile, then Invite friends.
    private var people: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Your people", count: store.contacts.isEmpty ? nil : store.contacts.count)
            if store.contacts.isEmpty {
                if store.contactsLoaded {
                    NoPeopleCard()
                } else {
                    ProgressView().tint(Theme.inkSoft).frame(maxWidth: .infinity)
                }
            } else {
                PeopleList(contacts: store.contacts)
            }
            NavigationLink {
                InviteView()
            } label: {
                Label("Invite friends", systemImage: "paperplane")
            }
            .buttonStyle(.outline)
            .padding(.top, 8)
        }
    }

    // MARK: Settings

    private var settings: some View {
        SettingsSection("Account") {
            Button {
                showSettings = true
            } label: {
                SettingsRow("Settings", systemImage: "gearshape",
                            detail: "Your name and photo, web chats, sign out", chevron: true)
            }
            .buttonStyle(.pressable)
        }
    }
}
