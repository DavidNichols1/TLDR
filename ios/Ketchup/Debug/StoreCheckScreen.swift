//
//  StoreCheckScreen.swift
//  Ketchup
//
//  `-screen store-check`: runs DeviceStore against a scratch folder with the
//  Breck fixtures and lists what passed, on screen and in the console
//  ("[store-check] PASS …"). No sign-in, no server, and the real folder is
//  never touched. It checks the round trips, the 400-message cap, one
//  user's copy hidden from the next, sign-out and launch clean-up, pruning
//  left chats, the server's page replacing a kept copy, old file shapes,
//  data protection, backup exclusion, and how long a big thread takes to
//  read back.
//

#if DEBUG
import SwiftUI

struct StoreCheckScreen: View {
    static let name = "store-check"

    @State private var results: [StoreCheck.Result] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Kicker("Offline check")
                    Text("Kept on the phone")
                        .font(.serif(.largeTitle))
                        .foregroundStyle(Theme.ink)
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSoft)
                }
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(results.indices, id: \.self) { i in
                        let result = results[i]
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(result.label)
                                .font(.mono(.caption, weight: .bold))
                                .foregroundStyle(result.skipped ? Theme.inkSoft : result.passed ? Theme.pickle : Theme.ketchupText)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.ink)
                                Text(result.detail)
                                    .font(.mono(.caption2))
                                    .foregroundStyle(Theme.inkSoft)
                            }
                        }
                        .padding(.vertical, 9)
                        if i < results.count - 1 { Divider().overlay(Theme.rule) }
                    }
                }
                .paperCard(padding: 14)
            }
            .padding(20)
        }
        .background(Theme.cream)
        .task {
            results = await StoreCheck.run()
            for r in results { print("[store-check] \(r.label) \(r.name): \(r.detail)") }
            print("[store-check] \(summary)")
        }
    }

    private var summary: String {
        if results.isEmpty { return "Running…" }
        let checked = results.filter { !$0.skipped }
        let skipped = results.count - checked.count
        return "\(checked.filter(\.passed).count) of \(checked.count) passed" + (skipped > 0 ? ", \(skipped) skipped" : "")
    }
}

enum StoreCheck {
    struct Result {
        let name: String
        let passed: Bool
        let detail: String
        /// Can't be checked here (the simulator has no data protection).
        var skipped = false

        var label: String { skipped ? "SKIP" : passed ? "PASS" : "FAIL" }
    }

    private static let userA = UUID(uuidString: "A0000000-0000-4000-8000-00000000000A")!
    private static let userB = UUID(uuidString: "A0000000-0000-4000-8000-00000000000B")!

    static func run() async -> [Result] {
        let root = URL.temporaryDirectory.appending(path: "store-check-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        var results: [Result] = []
        func check(_ name: String, _ passed: Bool, _ detail: String, skipped: Bool = false) {
            results.append(Result(name: name, passed: passed, detail: detail, skipped: skipped))
        }
        // `user` is who's signed in; each fresh store starts with an empty memory, so reads come off disk.
        var user: UUID? = userA
        func store() -> DeviceStore { DeviceStore(root: root) { user } }

        let breck = PreviewData.breckId
        let inbox = InboxSnapshot(me: Profile(id: userA, displayName: PreviewData.myName), chats: PreviewData.inbox)
        let messages = PreviewData.messages
        let sending = Message(id: UUID(), chatId: breck, sender: userA, body: "on my way", createdAt: .now, pending: true)
        let failed = Message(id: UUID(), chatId: breck, sender: userA, body: "oops", createdAt: .now, failed: true)

        // 1. Inbox round trip.
        let writer = store()
        writer.saveInbox(inbox)
        await writer.flush()
        let readInbox = store().inbox()
        check("Inbox round trip", readInbox?.chats == inbox.chats && readInbox?.me == inbox.me,
              "\(readInbox?.chats.count ?? 0) of \(inbox.chats.count) chats, name \(readInbox?.me?.displayName ?? "none")")

        // 2. Thread round trip; bubbles still sending or failed stay out.
        writer.saveThread(breck, messages: messages + [sending, failed], members: PreviewData.members)
        await writer.flush()
        let readThread = store().thread(breck)
        check("Thread round trip", readThread?.messages == messages && readThread?.members == PreviewData.members,
              "\(readThread?.messages.count ?? 0) of \(messages.count) messages, \(readThread?.members.count ?? 0) members, unsent left out")

        // 3. A long chat keeps its newest 400.
        let long = (0..<450).map { i in
            Message(id: UUID(), chatId: breck, sender: userA, body: "message \(i)",
                    createdAt: Date(timeIntervalSince1970: 1_793_000_000 + Double(i) * 60))
        }
        writer.saveThread(breck, messages: long, members: PreviewData.members)
        await writer.flush()
        let capped = store().thread(breck)?.messages ?? []
        check("Keeps the newest \(DeviceStore.threadMessages)",
              capped.count == DeviceStore.threadMessages && capped.first?.id == long[50].id && capped.last?.id == long.last?.id,
              "\(capped.count) kept, oldest is message \(capped.first.flatMap { m in long.firstIndex { $0.id == m.id } } ?? -1)")

        // 4. Reading a big thread back, off disk.
        let started = Date.now
        let timed = store().thread(breck)
        let ms = Date.now.timeIntervalSince(started) * 1000
        check("Reads a \(DeviceStore.threadMessages)-message thread fast", timed?.messages.count == DeviceStore.threadMessages && ms < 50,
              "\(ms.formatted(.number.precision(.fractionLength(1)))) ms on this device")

        // 5. One person's copy never shows to the next.
        user = userB
        let other = store()
        check("Another user sees nothing", other.inbox() == nil && other.thread(breck) == nil,
              "user B reads no inbox and no thread")
        user = userA

        // 6. Data protection and backups.
        let folder = root.appending(path: userA.uuidString.lowercased(), directoryHint: .isDirectory)
        let file = folder.appending(path: "inbox.json")
        #if targetEnvironment(simulator)
        check("Complete until first unlock", true, "the simulator has no data protection; run this on a phone", skipped: true)
        #else
        let protection = (try? FileManager.default.attributesOfItem(atPath: file.path(percentEncoded: false)))?[.protectionKey] as? FileProtectionType
        check("Complete until first unlock", protection == .completeUntilFirstUserAuthentication,
              protection.map { "\($0.rawValue)" } ?? "no protection attribute reported")
        #endif
        let excluded = (try? root.resourceValues(forKeys: [.isExcludedFromBackupKey]))?.isExcludedFromBackup
        check("Not in backups", excluded == true, "isExcludedFromBackup = \(excluded == true)")

        // 7. A chat you've left is forgotten.
        let pruner = store()
        pruner.saveThread(breck, messages: messages, members: PreviewData.members)
        let kept = PreviewData.inbox[1].id
        pruner.saveThread(kept, messages: [], members: [])
        pruner.keepThreads([kept])
        await pruner.flush()
        check("Forgets chats you left", pruner.thread(breck) == nil && store().thread(breck) == nil && store().thread(kept) != nil,
              "Breck gone from memory and disk, Roommates kept")

        // 8. The server's page replaces the kept copy.
        let keptIds = Set(long.map(\.id))
        let page = Array(long.suffix(200))
        let live = Message(id: UUID(), chatId: breck, sender: userB, body: "realtime", createdAt: .now)
        let merged = ThreadSnapshot.reconcile(long + [live, sending], kept: keptIds, page: page)
        check("Server page replaces the kept copy",
              merged.count == 202 && merged.first?.id == page.first?.id && merged.contains { $0.id == live.id } && merged.contains { $0.id == sending.id },
              "\(long.count) kept + 1 live + 1 sending, page of \(page.count): \(merged.count) left, no gap")

        // 9. A file in an old shape is ignored, not misread.
        let old = Data(#"{"version":0,"savedAt":0,"value":{"chats":[]}}"#.utf8)
        try? old.write(to: file)
        check("Ignores an old file shape", store().inbox() == nil, "version 0 file read as nothing")

        // 10. Launch clean-up: only the signed-in user's folder stays, and
        // with nobody signed in nothing is touched.
        let b = DeviceStore(root: root) { userB }
        b.saveInbox(inbox)
        await b.flush()
        let nobody = DeviceStore(root: root) { nil }
        nobody.tidy()
        await nobody.flush()
        let untouched = (try? FileManager.default.contentsOfDirectory(atPath: root.path(percentEncoded: false)))?.count ?? 0
        let tidier = store()
        tidier.tidy()
        await tidier.flush()
        let folders = (try? FileManager.default.contentsOfDirectory(atPath: root.path(percentEncoded: false))) ?? []
        check("Launch keeps only your folder", untouched == 2 && folders == [userA.uuidString.lowercased()],
              "signed out: \(untouched) folders kept; signed in: \(folders.count) left")

        // 11. Signing out deletes everything.
        tidier.saveInbox(inbox)
        tidier.wipe()
        await tidier.flush()
        let gone = !FileManager.default.fileExists(atPath: root.path(percentEncoded: false))
        check("Sign-out wipes it all", gone && tidier.inbox() == nil, gone ? "folder deleted, memory empty" : "folder still there")

        return results
    }
}
#endif
