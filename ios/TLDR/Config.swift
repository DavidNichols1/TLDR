//
//  Config.swift
//  TLDR
//
//  Backend coordinates. The publishable key is safe to ship in the app: it
//  only grants what Row Level Security allows. The service-role key and the
//  Meta Model API key never appear in the app or this repo.
//

import Foundation

enum Config {
    /// Supabase project "TLDR".
    nonisolated static let supabaseURL = URL(string: "https://cfqlnthmqwkhjbhylvgu.supabase.co")!

    /// Publishable (client) key — not a secret, RLS is the gate.
    nonisolated static let publishableKey = "sb_publishable_wBQM04epqb9p6riHKjGmCA_YNF9OpZl"

    /// Realtime websocket (Phoenix protocol).
    nonisolated static var realtimeURL: URL {
        var c = URLComponents(url: supabaseURL, resolvingAgainstBaseURL: false)!
        c.scheme = "wss"
        c.path = "/realtime/v1/websocket"
        c.queryItems = [URLQueryItem(name: "apikey", value: publishableKey),
                        URLQueryItem(name: "vsn", value: "1.0.0")]
        return c.url!
    }
}
