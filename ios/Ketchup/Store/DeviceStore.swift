//
//  DeviceStore.swift
//  Ketchup
//
//  What the phone keeps between launches, so the app opens on your inbox
//  and a chat's recent messages at once and refreshes from the server
//  behind them: the inbox (my_chats and your name) and, per chat, its
//  newest messages and members. Adapted from AurariaGO's ResponseCache.
//
//  Where: Application Support/Ketchup/<user id>/, one JSON file per thing,
//  so one person's chats never show to the next. Signing out deletes the
//  whole Ketchup folder. Files are written with complete-until-first-unlock
//  data protection, and the folder is excluded from backups, so it stays on
//  this phone.
//
//  Reads come from memory, or from disk on the main actor (a few ms, so a
//  screen can open on them in its first frame). Writes are encoded here and
//  land on a background queue in order; the copy in memory means a read
//  right after a write already sees it.
//
//  The server always wins: AppModel and ChatModel show what's kept here only
//  until the server's first answer replaces it.
//

import Foundation

/// The inbox as it last came from the server, and the name you go by.
struct InboxSnapshot: Codable {
    var me: Profile?
    var chats: [ChatSummary]
}

/// A chat's newest messages (oldest first) and its members, as last seen.
struct ThreadSnapshot: Codable {
    var messages: [Message]
    var members: [Member]

    /// Once the server's newest page is in: drops the kept messages it
    /// didn't send back (older than the page, or gone), so a kept copy
    /// never leaves a gap or a ghost. Messages that arrived live meanwhile
    /// and bubbles still sending stay.
    static func reconcile(_ messages: [Message], kept: Set<UUID>, page: [Message]) -> [Message] {
        let fresh = Set(page.map(\.id))
        return messages.filter { !kept.contains($0.id) || fresh.contains($0.id) }
    }
}

final class DeviceStore {

    /// The signed-in user's folder.
    static let shared: DeviceStore = {
        #if DEBUG
        // Offline previews (`-screen`) never read, write or tidy the real
        // folder, even with a real session in the Keychain. `chat-kept`
        // keeps its copy in a scratch folder.
        if PreviewData.isActive {
            return DeviceStore(root: URL.temporaryDirectory.appending(path: "Ketchup-preview")) { PreviewData.storeUser }
        }
        #endif
        return DeviceStore(root: defaultRoot) { Supabase.shared.userId }
    }()

    /// Messages kept per chat: enough for the 302-message demo chat's first
    /// load (302 unread plus 25 before them).
    static let threadMessages = 400

    /// Bumped when a file's shape changes; older files are ignored.
    private static let version = 1

    private let root: URL
    private let user: () -> UUID?
    private let queue = DispatchQueue(label: "com.vibetemp.ketchup.device-store", qos: .utility)
    /// The latest copy of each file, by path.
    private var memory: [String: Any] = [:]

    init(root: URL, user: @escaping () -> UUID?) {
        self.root = root
        self.user = user
    }

    static var defaultRoot: URL {
        URL.applicationSupportDirectory.appending(path: "Ketchup", directoryHint: .isDirectory)
    }

    // MARK: Inbox

    func inbox() -> InboxSnapshot? {
        read(InboxSnapshot.self, at: "inbox.json")
    }

    func saveInbox(_ inbox: InboxSnapshot) {
        write(inbox, at: "inbox.json")
    }

    // MARK: Threads

    func thread(_ chat: UUID) -> ThreadSnapshot? {
        read(ThreadSnapshot.self, at: Self.threadPath(chat))
    }

    /// Keeps the newest `threadMessages` confirmed messages (no bubbles still
    /// sending or failed) and the members.
    func saveThread(_ chat: UUID, messages: [Message], members: [Member]) {
        let confirmed = messages.filter { !$0.pending && !$0.failed }
        write(ThreadSnapshot(messages: Array(confirmed.suffix(Self.threadMessages)), members: members),
              at: Self.threadPath(chat))
    }

    /// Forgets every chat not in `chats` (left, or removed from), so its
    /// messages don't stay on the phone.
    func keepThreads(_ chats: Set<UUID>) {
        guard let folder = folder() else { return }
        let threads = folder.appending(path: "threads", directoryHint: .isDirectory)
        let keep = Set(chats.map { Self.key(folder.appending(path: Self.threadPath($0))) })
        for key in memory.keys where key.hasPrefix(Self.key(threads)) && !keep.contains(key) {
            memory[key] = nil
        }
        let names = Set(chats.map { "\($0.uuidString.lowercased()).json" })
        queue.async {
            let files = (try? FileManager.default.contentsOfDirectory(at: threads, includingPropertiesForKeys: nil)) ?? []
            for file in files where !names.contains(file.lastPathComponent) {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    // MARK: Everything

    /// Signing out: deletes every user's folder, so nothing of theirs stays.
    func wipe() {
        memory.removeAll()
        let root = root
        queue.async { try? FileManager.default.removeItem(at: root) }
    }

    /// At launch: deletes any folder that isn't the signed-in user's (a
    /// sign-out the app was closed in the middle of). With nobody signed in
    /// it leaves everything: sign-out already wiped, and a session that
    /// couldn't be read yet isn't a sign-out.
    func tidy() {
        guard let current = user()?.uuidString.lowercased() else { return }
        let root = root
        queue.async {
            let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            for folder in folders where folder.lastPathComponent != current {
                try? FileManager.default.removeItem(at: folder)
            }
        }
    }

    // MARK: Plumbing

    /// A file and when it was written. `version` guards against old shapes.
    private struct Kept<Value: Codable>: Codable {
        let version: Int
        let savedAt: Date
        let value: Value
    }

    private static func threadPath(_ chat: UUID) -> String {
        "threads/\(chat.uuidString.lowercased()).json"
    }

    /// A file's key in `memory`: its path.
    private static func key(_ url: URL) -> String {
        url.path(percentEncoded: false)
    }

    private func folder() -> URL? {
        guard let user = user() else { return nil }
        return root.appending(path: user.uuidString.lowercased(), directoryHint: .isDirectory)
    }

    private func read<Value: Codable>(_ type: Value.Type, at path: String) -> Value? {
        guard let url = folder()?.appending(path: path) else { return nil }
        if let value = memory[Self.key(url)] as? Value { return value }
        #if DEBUG
        let started = Date.now
        #endif
        // Dates as plain numbers, not the server's strings: an exact round
        // trip, and several times faster to read.
        guard let data = try? Data(contentsOf: url),
              let kept = try? JSONDecoder().decode(Kept<Value>.self, from: data),
              kept.version == Self.version else { return nil }
        memory[Self.key(url)] = kept.value
        #if DEBUG
        print("[store] read \(path.hasPrefix("threads") ? "a thread" : path), \(data.count / 1024) KB in \(Self.ms(since: started)) ms")
        #endif
        return kept.value
    }

    private func write<Value: Codable>(_ value: Value, at path: String) {
        guard let folder = folder(),
              let data = try? JSONEncoder().encode(Kept(version: Self.version, savedAt: .now, value: value)) else { return }
        let url = folder.appending(path: path)
        memory[Self.key(url)] = value
        let root = root
        queue.async { Self.store(data, at: url, root: root) }
    }

    /// Runs on the queue. Creates the folders on first use, protected and
    /// out of backups.
    nonisolated private static func store(_ data: Data, at url: URL, root: URL) {
        let manager = FileManager.default
        let folder = url.deletingLastPathComponent()
        if !manager.fileExists(atPath: folder.path(percentEncoded: false)) {
            try? manager.createDirectory(at: folder, withIntermediateDirectories: true,
                                         attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            var root = root
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? root.setResourceValues(values)
        }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    #if DEBUG
    private static func ms(since start: Date) -> String {
        (Date.now.timeIntervalSince(start) * 1000).formatted(.number.precision(.fractionLength(1)))
    }

    /// Waits for every queued write (the store check, `-screen store-check`).
    func flush() async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            queue.async { done.resume() }
        }
    }
    #endif
}
