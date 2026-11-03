//
//  Supabase.swift
//  Ketchup
//
//  A small hand-rolled Supabase client: Auth (email code), PostgREST, RPCs
//  and edge functions over plain URLSession, so the app has zero
//  dependencies. Adapted from David's AurariaGO client: same token refresh
//  rule (only Supabase Auth refusing the refresh token signs you out) and
//  the session kept in the Keychain.
//

import Foundation
import Security

// MARK: - Errors

enum APIError: LocalizedError {
    case notSignedIn
    case server(String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .notSignedIn:   return "Sign in to continue."
        case .server(let m): return m
        case .badResponse:   return "The server sent something unexpected. Try again."
        }
    }
}

// MARK: - Session

struct AuthSession: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
    let userId: UUID
    let email: String
    /// Unix seconds when the access token expires.
    let expiresAt: TimeInterval

    var isExpiringSoon: Bool { Date().timeIntervalSince1970 > expiresAt - 60 }
}

// MARK: - JSON

enum JSON {
    /// Postgres timestamps arrive with 0–6 fractional digits and an offset
    /// ("2026-11-02T19:41:05.123456+00:00"); Foundation's ISO 8601 parser
    /// wants at most 3, so trim before parsing.
    nonisolated static func date(from raw: String) -> Date? {
        // Postgres text form ("2026-11-02 19:41:05+00") as well as ISO.
        var s = raw.replacingOccurrences(of: " ", with: "T")
        if let dot = s.firstIndex(of: ".") {
            let afterDot = s.index(after: dot)
            let zone = s[afterDot...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" }) ?? s.endIndex
            let digits = s[afterDot..<zone]
            let ms = String(digits.prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0)
            s = String(s[..<dot]) + "." + ms + String(s[zone...])
        }
        if !s.hasSuffix("Z"), s.count > 6 {
            // "+00" → "+00:00"
            let tail = s.suffix(3)
            if (tail.first == "+" || tail.first == "-"), tail.dropFirst().allSatisfy(\.isNumber) {
                s += ":00"
            }
        }
        return withFraction.date(from: s) ?? plain.date(from: s)
    }

    nonisolated(unsafe) private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    nonisolated static func iso(_ date: Date) -> String {
        withFraction.string(from: date)
    }

    nonisolated static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            if let date = JSON.date(from: s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath,
                                                    debugDescription: "Unparseable date: \(s)"))
        }
        return d
    }
}

// MARK: - Client

final class Supabase {

    static let shared = Supabase()
    private init() { session = Keychain.load() }

    /// Called whenever the session changes (sign-in, refresh, sign-out).
    var onSessionChange: ((AuthSession?) -> Void)?

    private(set) var session: AuthSession? {
        didSet {
            if let session { Keychain.save(session) } else { Keychain.delete() }
            if oldValue != session { onSessionChange?(session) }
        }
    }

    var userId: UUID? { session?.userId }

    // MARK: Auth (email code)

    /// Emails a one-time code. Creates the account on first sign-in.
    func sendCode(to email: String) async throws {
        try await postAuth(path: "/auth/v1/otp", body: ["email": email, "create_user": true])
    }

    func verifyCode(email: String, code: String) async throws {
        let data = try await postAuth(path: "/auth/v1/verify",
                                      body: ["type": "email", "email": email, "token": code])
        session = try Self.parseSession(from: data)
    }

    func signOut() async {
        if let token = session?.accessToken {
            _ = try? await postAuth(path: "/auth/v1/logout", body: [:], bearer: token)
        }
        session = nil
    }

    /// A valid access token (refreshed if it's about to lapse), for Realtime.
    func freshAccessToken() async -> String? {
        try? await refreshIfNeeded()
        return session?.accessToken
    }

    // MARK: PostgREST / RPC / functions

    /// `shares`: an identical call already on its way answers this one too
    /// (InFlight.swift). Reads share by default; writes never should.
    @discardableResult
    func rest(_ method: String, _ path: String,
              query: [URLQueryItem] = [],
              body: Data? = nil,
              prefer: String? = nil,
              shares: Bool? = nil) async throws -> Data {
        #if DEBUG
        if PreviewData.isActive { throw Self.offline }
        #endif
        guard let user = session?.userId else { throw APIError.notSignedIn }
        guard shares ?? (method == "GET") else {
            return try await send(method, path, query: query, body: body, prefer: prefer)
        }
        let key = [user.uuidString, method, path, query.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&"),
                   body.map { String(decoding: $0, as: UTF8.self) } ?? ""].joined(separator: "|")
        return try await reads.share(key) {
            try await self.send(method, path, query: query, body: body, prefer: prefer)
        }
    }

    /// Reads on their way, by user, path, query and body.
    let reads = InFlight<Data>()

    private func send(_ method: String, _ path: String, query: [URLQueryItem], body: Data?, prefer: String?) async throws -> Data {
        try await refreshIfNeeded()

        var components = URLComponents(url: Config.supabaseURL.appendingPathComponent(path),
                                       resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.timeoutInterval = path.hasPrefix("/functions/") ? 90 : 30
        request.setValue(Config.publishableKey, forHTTPHeaderField: "apikey")
        if let token = session?.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.throwIfError(data: data, response: response)
        return data
    }

    func rpc(_ name: String, _ args: [String: Any] = [:], shares: Bool = false) async throws -> Data {
        try await rest("POST", "/rest/v1/rpc/\(name)", body: JSONSerialization.data(withJSONObject: args), shares: shares)
    }

    func function(_ name: String, _ args: [String: Any]) async throws -> Data {
        try await rest("POST", "/functions/v1/\(name)", body: JSONSerialization.data(withJSONObject: args))
    }

    // MARK: Plumbing

    #if DEBUG
    /// Offline preview mode (`-screen`) never talks to the server, whatever a screen does.
    private static let offline = APIError.server("Offline preview: nothing goes to the server.")
    #endif

    @discardableResult
    private func postAuth(path: String, body: [String: Any], bearer: String? = nil) async throws -> Data {
        let (data, response) = try await sendAuth(path: path, body: body, bearer: bearer)
        try Self.throwIfError(data: data, response: response)
        return data
    }

    private func sendAuth(path: String, body: [String: Any], bearer: String? = nil) async throws -> (Data, URLResponse) {
        #if DEBUG
        if PreviewData.isActive { throw Self.offline }
        #endif
        // Not appendingPathComponent: the refresh path carries a query string.
        guard let url = URL(string: path, relativeTo: Config.supabaseURL) else { throw APIError.badResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(Config.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await URLSession.shared.data(for: request)
    }

    /// Concurrent callers share one refresh instead of each spending the
    /// same refresh token.
    private var refreshTask: Task<Void, Error>?

    private func refreshIfNeeded() async throws {
        guard let current = session, current.isExpiringSoon else { return }
        if let inFlight = refreshTask {
            try await inFlight.value
            return
        }
        let task = Task<Void, Error> {
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await sendAuth(path: "/auth/v1/token?grant_type=refresh_token",
                                                      body: ["refresh_token": current.refreshToken])
            } catch {
                throw error  // offline: keep the session, try again next request
            }
            // Only Supabase Auth refusing the token (400/401) ends the session.
            if let http = response as? HTTPURLResponse, http.statusCode == 400 || http.statusCode == 401 {
                session = nil
                throw APIError.notSignedIn
            }
            try Self.throwIfError(data: data, response: response)
            session = try Self.parseSession(from: data)
        }
        refreshTask = task
        defer { refreshTask = nil }
        try await task.value
    }

    private static func parseSession(from data: Data) throws -> AuthSession {
        struct AuthResponse: Decodable {
            struct User: Decodable { let id: UUID; let email: String? }
            let access_token: String
            let refresh_token: String
            let expires_at: TimeInterval?
            let expires_in: TimeInterval?
            let user: User
        }
        let auth = try JSONDecoder().decode(AuthResponse.self, from: data)
        return AuthSession(accessToken: auth.access_token,
                           refreshToken: auth.refresh_token,
                           userId: auth.user.id,
                           email: auth.user.email ?? "",
                           expiresAt: auth.expires_at ?? Date().timeIntervalSince1970 + (auth.expires_in ?? 3600))
    }

    private static func throwIfError(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw APIError.badResponse }
        guard !(200...299).contains(http.statusCode) else { return }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["message", "msg", "error_description", "error"] {
                if let m = json[key] as? String, !m.isEmpty {
                    throw APIError.server(friendly(m, status: http.statusCode))
                }
            }
        }
        throw APIError.server("Request failed (\(http.statusCode)). Try again.")
    }

    private static func friendly(_ raw: String, status: Int) -> String {
        let lower = raw.lowercased()
        if lower.contains("sending too fast") { return "Slow down a little." }
        if lower.contains("token has expired") || lower.contains("otp") && lower.contains("invalid") {
            return "That code didn't work. Check it or send a new one."
        }
        if lower.contains("row-level security") { return "That isn't allowed in this chat." }
        if status == 429 || lower.contains("rate limit") { return "Too many tries. Wait a minute and try again." }
        return raw
    }
}

// MARK: - Keychain

private enum Keychain {
    private static let service = "com.vibetemp.ketchup.session"

    static func save(_ session: AuthSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        var query = base
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load() -> AuthSession? {
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }

    static func delete() { SecItemDelete(base as CFDictionary) }

    private static var base: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: "session"]
    }
}
