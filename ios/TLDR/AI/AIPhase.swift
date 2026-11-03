//
//  AIPhase.swift
//  TLDR
//
//  The state of one Muse Spark request, and the words for what went wrong.
//

import Foundation

enum AIPhase<Value> {
    case idle
    case loading
    case done(Value)
    case failed(String)

    var isLoading: Bool { if case .loading = self { true } else { false } }
    var value: Value? { if case .done(let v) = self { v } else { nil } }
}

enum AIErrors {
    /// A readable sentence for any failure on the way to Muse Spark —
    /// including the edge function not being deployed yet (404 from the
    /// gateway) or not configured (503) or the model failing (502).
    static func message(for error: Error) -> String {
        if let url = error as? URLError {
            switch url.code {
            case .timedOut: return "Muse Spark took too long. Try again."
            case .notConnectedToInternet, .networkConnectionLost: return "You're offline. Reconnect and try again."
            default: return "Couldn't reach Muse Spark. Try again."
            }
        }
        if error is DecodingError {
            return "Muse Spark sent back something unexpected. Try again."
        }
        if case APIError.server(let raw) = error {
            let lower = raw.lowercased()
            if lower.contains("function") && lower.contains("not found") {
                return "Muse Spark isn't switched on yet. Try again soon."
            }
            if lower.hasPrefix("request failed (50") {
                return "Muse Spark is busy right now. Try again in a moment."
            }
            return raw
        }
        return error.localizedDescription
    }
}
