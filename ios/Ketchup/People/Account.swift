//
//  Account.swift
//  Ketchup
//
//  The account side of AppModel that Settings needs: your email, signing
//  out, and deleting the account.
//

import Foundation

/// How Settings closes when you leave the account. The sheet goes away
/// first and this runs after (`AppModel.leave(_:)`), so nothing is left on
/// screen when the signed-in home is replaced by sign-in. Both forget the
/// web-chat sign-ins.
enum SettingsExit {
    case signOut
    /// The server already deleted it (`KetchupAPI.deleteAccount()`).
    case accountDeleted
}

extension AppModel {
    /// The email you sign in with.
    var accountEmail: String? {
        #if DEBUG
        if previewUser != nil { return PeoplePreviewScreen.email }
        #endif
        return session?.email
    }

    /// Deletes the account on the server, for good: the rows, then the photos
    /// they uploaded, both server side (the delete-account edge function), so
    /// a delete that fails leaves everything as it was. Settings then closes
    /// and `leave(.accountDeleted)` signs out. A no-op in offline previews.
    func deleteAccount() async throws {
        guard previewUser == nil else { return }
        try await KetchupAPI.deleteAccount()
    }

    /// Signs out on this iPhone, and forgets the Instagram and Snapchat
    /// sign-ins in Ketchup's web views, so nothing of this account stays for
    /// whoever signs in next. Offline previews touch nothing: their web views
    /// share the phone's real website data.
    func leave(_ exit: SettingsExit) async {
        guard previewUser == nil else { return }
        for source in WebChatSource.all { await source.forgetSavedData() }
        await signOut()
    }
}
