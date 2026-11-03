//
//  InFlight.swift
//  Ketchup
//
//  One request for identical work already on its way: a second caller waits
//  for the first one's answer instead of asking the server again. Supabase
//  uses it for reads (every GET, and my_chats), so the inbox's 15-second
//  refresh, a pull to refresh and coming back from a chat share one call,
//  and so do the members a chat, its info sheet and a new sender ask for.
//  The work runs to the end even if the caller that started it goes away,
//  so everyone waiting still gets the answer.
//

import Foundation

final class InFlight<Value: Sendable> {
    private var running: [String: Task<Value, Error>] = [:]

    #if DEBUG
    /// Calls that did the work, and callers that shared someone else's (the
    /// speed check, `-screen store-check`).
    private(set) var started = 0
    private(set) var joined = 0
    #endif

    func share(_ key: String, _ work: @escaping () async throws -> Value) async throws -> Value {
        if let task = running[key] {
            #if DEBUG
            joined += 1
            #endif
            return try await task.value
        }
        let task = Task { try await work() }
        running[key] = task
        #if DEBUG
        started += 1
        #endif
        defer { running[key] = nil }
        return try await task.value
    }
}
