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
/// screen when the signed-in home is replaced by sign-in.
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

    /// Deletes the account on the server, for good. Settings then closes and
    /// `leave(.accountDeleted)` signs out. A no-op in offline previews.
    func deleteAccount() async throws {
        guard previewUser == nil else { return }
        // SQL can't delete Storage files, so the avatar and the photos you
        // sent go through the Storage API before the rows do.
        await ChatPhotos.deleteMine(app: self)
        try await KetchupAPI.deleteAccount()
    }

    /// Signs out on this iPhone. After a deleted account it also forgets the
    /// Instagram and Snapchat sign-ins in Ketchup's web views: nothing of
    /// that account stays behind for whoever signs in next.
    func leave(_ exit: SettingsExit) async {
        if exit == .accountDeleted {
            for source in WebChatSource.all { await source.forgetSavedData() }
        }
        await signOut()
    }
}
