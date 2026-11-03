//
//  Storage.swift
//  Ketchup
//
//  Supabase Storage on top of the client in Supabase.swift: upload (with
//  progress), public URLs for public buckets, signed URLs for private ones,
//  and delete. Row Level Security on storage.objects decides who may do
//  what (supabase/migrations/0006_photos.sql); photos are downloaded and
//  cached by Photos/RemoteImages.swift.
//

import Foundation

/// A file in a Storage bucket.
nonisolated struct StorageObject: Hashable, Sendable {
    let bucket: String
    let path: String

    /// "bucket/path": the image cache's key for this file.
    var key: String { "\(bucket)/\(path)" }

    /// Served from a fixed public URL; anything else needs a signed URL.
    var isPublic: Bool { bucket == Storage.avatars }

    /// A profile photo: public, "<uid>/<uuid>.jpg".
    static func avatar(_ path: String) -> StorageObject { StorageObject(bucket: Storage.avatars, path: path) }
}

enum Storage {

    /// Profile photos. Public: anyone with a path can load it, nobody can list.
    nonisolated static let avatars = "avatars"
    /// Photos sent in chats. Private: only the chat's members, by signed URL.
    nonisolated static let chatMedia = "chat-media"

    /// A file in a public bucket, straight from its fixed URL (no token).
    nonisolated static func publicURL(_ object: StorageObject) -> URL {
        Config.supabaseURL.appending(path: "storage/v1/object/public/\(object.bucket)/\(object.path)")
    }

    /// Uploads `data` as a new file. Paths are one-time uuids, so a file never
    /// changes: the CDN and every phone may keep it for a year. `progress`
    /// gets 0...1 from URLSession's queue as the bytes go out.
    static func upload(_ data: Data, to object: StorageObject, contentType: String = "image/jpeg",
                       progress: (@Sendable (Double) -> Void)? = nil) async throws {
        #if DEBUG
        if PreviewData.isActive { throw APIError.server("Offline preview: nothing goes to the server.") }
        #endif
        guard let token = await Supabase.shared.freshAccessToken() else { throw APIError.notSignedIn }
        var request = URLRequest(url: Config.supabaseURL.appending(path: "storage/v1/object/\(object.bucket)/\(object.path)"))
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue(Config.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("max-age=31536000, immutable", forHTTPHeaderField: "Cache-Control")

        let delegate = progress.map(UploadProgress.init)
        let (body, response) = try await URLSession.shared.upload(for: request, from: data, delegate: delegate)
        try check(body, response)
    }

    /// A URL for a file in a private bucket, good for `expiresIn` seconds.
    static func signedURL(_ object: StorageObject, expiresIn: Int = 3600) async throws -> URL {
        let data = try await Supabase.shared.rest("POST", "/storage/v1/object/sign/\(object.bucket)/\(object.path)",
                                                  body: JSONSerialization.data(withJSONObject: ["expiresIn": expiresIn]))
        struct Signed: Decodable { let signedURL: String }
        let signed = try JSONDecoder().decode(Signed.self, from: data)
        guard let url = signedURL(from: signed.signedURL) else { throw APIError.badResponse }
        return url
    }

    /// Signed URLs for many files in one bucket in one request, by path.
    /// Paths the server won't sign (missing, not allowed) are left out.
    static func signedURLs(bucket: String, paths: [String], expiresIn: Int = 3600) async throws -> [String: URL] {
        guard !paths.isEmpty else { return [:] }
        let body: [String: Any] = ["expiresIn": expiresIn, "paths": paths]
        let data = try await Supabase.shared.rest("POST", "/storage/v1/object/sign/\(bucket)",
                                                  body: JSONSerialization.data(withJSONObject: body))
        struct Signed: Decodable { let path: String?; let signedURL: String?; let error: String? }
        var urls: [String: URL] = [:]
        for row in try JSONDecoder().decode([Signed].self, from: data) where row.error == nil {
            if let path = row.path, let url = row.signedURL.flatMap(signedURL(from:)) { urls[path] = url }
        }
        return urls
    }

    /// Deletes files through the Storage API. (Deleting storage.objects rows
    /// with SQL would leave the files behind.)
    static func remove(_ objects: [StorageObject]) async throws {
        for (bucket, files) in Dictionary(grouping: objects, by: \.bucket) {
            let body = try JSONSerialization.data(withJSONObject: ["prefixes": files.map(\.path)])
            try await Supabase.shared.rest("DELETE", "/storage/v1/object/\(bucket)", body: body)
        }
    }

    // MARK: Plumbing

    /// The API answers with a path under /storage/v1 ("/object/sign/…?token=…").
    private static func signedURL(from relative: String) -> URL? {
        URL(string: Config.supabaseURL.absoluteString + "/storage/v1" + relative)
    }

    /// Storage's errors are `{statusCode, error, message}`.
    private static func check(_ data: Data, _ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw APIError.badResponse }
        guard !(200...299).contains(http.statusCode) else { return }
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let message = (json?["message"] as? String ?? "").lowercased()
        let status = (json?["statusCode"] as? String).flatMap(Int.init) ?? http.statusCode
        // Every path is a one-time uuid, so a file already there is this one,
        // from an earlier try whose reply got lost: it's uploaded. Storage says
        // so as a 409, or a 400 "Asset Already Exists", KeyAlreadyExists or Duplicate.
        let code = ((json?["code"] as? String) ?? (json?["error"] as? String) ?? "").lowercased()
        if status == 409 || message.contains("already exists") || code.contains("alreadyexists")
            || code == "already_exists" || code == "duplicate" { return }
        if status == 413 || message.contains("maximum allowed size") {
            throw APIError.server("That photo is too big to send.")
        }
        if status == 415 || message.contains("mime type") {
            throw APIError.server("That file isn't a photo Ketchup can send.")
        }
        if message.contains("row-level security") {
            // The app only writes where it may, so this is the hourly cap.
            throw APIError.server("That's a lot of photos for one hour. Try again a bit later.")
        }
        if status == 401 { throw APIError.notSignedIn }
        throw APIError.server("The photo didn't upload (\(status)). Try again.")
    }
}

/// Reports an upload's progress from URLSession's delegate queue.
private nonisolated final class UploadProgress: NSObject, URLSessionTaskDelegate, Sendable {
    private let report: @Sendable (Double) -> Void

    init(_ report: @escaping @Sendable (Double) -> Void) {
        self.report = report
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        report(min(1, Double(totalBytesSent) / Double(totalBytesExpectedToSend)))
    }
}
