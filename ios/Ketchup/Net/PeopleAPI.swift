//
//  PeopleAPI.swift
//  Ketchup
//
//  Server calls for your account and the people around you (migration
//  0007). Like the rest of KetchupAPI, they run as the signed-in member, so
//  Row Level Security decides what each one may touch.
//

import Foundation

extension KetchupAPI {

    // MARK: Account

    /// Deletes the signed-in account and everything it wrote, for good
    /// (`delete_account()`): profile, memberships, messages, catch-ups, and
    /// friends' saved catch-ups that read those messages.
    static func deleteAccount() async throws {
        _ = try await Supabase.shared.rpc("delete_account")
    }
}
