//
//  ChatModel.swift
//  TLDR
//
//  One open chat: its messages, members, live updates, sending, the read
//  cursor, and the two Muse Spark requests.
//
//  Sending is optimistic. The bubble appears at once with a UUID the app
//  picks, and the insert uses that same UUID as the row id (messages grants
//  insert on id). The insert's reply, the Realtime echo and the polling
//  fallback all merge by id, so whichever lands first confirms the bubble
//  and the others are no-ops.
//
//  Read cursor (mark_read): opening a chat does NOT mark it read. The point
//  of the app is "Catch me up · 312 unread", and the edge function
//  summarizes everything after the server-side cursor — so moving it on
//  open would leave nothing to catch up on. The cursor moves only when:
//    1. a catch-up comes back (to the newest message it covered),
//    2. the user scrolls themselves down to the bottom of the thread,
//    3. the user sends a message (the server's apply_message trigger moves
//       the sender's cursor), or
//    4. the user leaves having seen the bottom (short threads that fit on
//       one screen never get scrolled).
//

import Foundation
import Observation

@Observable
final class ChatModel {

    private(set) var chat: ChatSummary
    let myId: UUID

    private(set) var messages: [Message] = []
    private(set) var members: [Member] = []
    private(set) var names: [UUID: String] = [:]
    private(set) var loaded = false
    private(set) var loadError: String?
    private(set) var hasOlder = false
    private(set) var loadingOlder = false

    /// Unread when the chat opened; drives the "Catch me up" button until
    /// the cursor moves.
    private(set) var unreadCount: Int
    /// The same number frozen at open, for the "N new messages" divider.
    private(set) var unreadAtOpen = 0
    /// Where the "new messages" divider goes.
    private(set) var firstUnreadId: UUID?
    private let cursorAtOpen: Date
    /// True once the bottom of the thread has been on screen.
    var sawBottom = false

    // Muse Spark
    private(set) var catchUp: AIPhase<BriefResponse<CatchUp>> = .idle
    private(set) var answer: AIPhase<BriefResponse<ChatAnswer>> = .idle
    private(set) var lastQuestion = ""

    private static let pageSize = 200

    @ObservationIgnored
    lazy var realtime = ChatRealtime(chatId: chat.id) { [weak self] message in
        self?.merge([message])
    }

    init(chat: ChatSummary, myId: UUID) {
        self.chat = chat
        self.myId = myId
        self.unreadCount = chat.unreadCount
        self.cursorAtOpen = chat.lastReadAt
    }

    // MARK: - Loading

    func open() async {
        realtime.start()
        guard !loaded else { return }
        do {
            let page = try await TLDRAPI.messages(in: chat.id, limit: Self.pageSize)
            hasOlder = page.count >= Self.pageSize
            merge(page)
            loaded = true
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
        await loadMembers()
        computeUnread()
    }

    func close() {
        realtime.stop()
        if sawBottom { markRead() }
    }

    func loadMembers() async {
        guard let list = try? await TLDRAPI.members(of: chat.id) else { return }
        members = list
        for m in list { names[m.userId] = m.name }
    }

    func loadOlder() async {
        guard hasOlder, !loadingOlder, let oldest = messages.first(where: { !$0.pending && !$0.failed }) else { return }
        loadingOlder = true
        defer { loadingOlder = false }
        guard let page = try? await TLDRAPI.messages(in: chat.id, before: oldest.createdAt, limit: Self.pageSize) else { return }
        hasOlder = page.count >= Self.pageSize
        merge(page)
    }

    /// Pages back until `id` is loaded (a ref can point at an old message).
    /// False if it still isn't here.
    func ensureLoaded(_ id: UUID) async -> Bool {
        var pages = 0
        while !messages.contains(where: { $0.id == id }), hasOlder, pages < 6 {
            await loadOlder()
            pages += 1
        }
        return messages.contains { $0.id == id }
    }

    /// The fallback while Realtime is down: everything newer than what we have.
    func poll() async {
        guard loaded else { return }
        let newest = messages.last(where: { !$0.pending && !$0.failed })?.createdAt ?? chat.createdAt
        guard let fresh = try? await TLDRAPI.messages(in: chat.id, after: newest) else { return }
        merge(fresh)
    }

    private func computeUnread() {
        let unread = messages.filter { $0.createdAt > cursorAtOpen && $0.sender != myId && !$0.pending }
        firstUnreadId = unread.first?.id
        unreadCount = max(unreadCount, unread.count)
        if unreadCount == 0 { firstUnreadId = nil }
        unreadAtOpen = unreadCount
    }

    // MARK: - Merging

    /// Adds or confirms messages by id. Confirmed messages sort by server
    /// time; bubbles still in flight stay at the bottom in send order.
    private func merge(_ incoming: [Message]) {
        guard !incoming.isEmpty else { return }
        var unknownSender = false
        for var m in incoming where m.chatId == chat.id {
            m.pending = false
            m.failed = false
            if let i = messages.firstIndex(where: { $0.id == m.id }) {
                messages[i] = m
            } else {
                messages.append(m)
            }
            if names[m.sender] == nil { unknownSender = true }
        }
        let confirmed = messages.filter { !$0.pending && !$0.failed }
            .sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
        let inFlight = messages.filter { $0.pending || $0.failed }
        messages = confirmed + inFlight
        // Someone new joined since we loaded members.
        if unknownSender { Task { await loadMembers() } }
    }

    // MARK: - Sending

    func send(_ text: String) {
        let id = UUID()
        messages.append(Message(id: id, chatId: chat.id, sender: myId, body: text, createdAt: .now, pending: true))
        // The server moves the sender's own cursor on insert (apply_message).
        caughtUp()
        Task { await deliver(id) }
    }

    func retry(_ id: UUID) {
        guard let i = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[i].failed = false
        messages[i].pending = true
        Task { await deliver(id) }
    }

    private func deliver(_ id: UUID) async {
        guard let local = messages.first(where: { $0.id == id }), local.pending else { return }
        do {
            let row = try await TLDRAPI.send(id: id, chat: chat.id, body: local.body)
            merge([row])
        } catch {
            guard let i = messages.firstIndex(where: { $0.id == id }), messages[i].pending else { return }
            if error.localizedDescription.lowercased().contains("duplicate key") {
                // An earlier attempt did land (its reply was lost); it's sent.
                messages[i].pending = false
            } else {
                messages[i].pending = false
                messages[i].failed = true
            }
        }
    }

    // MARK: - Read cursor

    /// The user scrolled down to the bottom themselves.
    func reachedBottomByScrolling() {
        sawBottom = true
        if unreadCount > 0 { markRead() }
    }

    private func markRead(at date: Date? = nil) {
        caughtUp()
        let id = chat.id
        Task { try? await TLDRAPI.markRead(id, at: date) }
    }

    private func caughtUp() {
        unreadCount = 0
    }

    // MARK: - Muse Spark

    /// Starts a catch-up unless one is running or a finished one still
    /// covers everything unread.
    func catchUpIfNeeded() async {
        switch catchUp {
        case .loading: return
        case .done where unreadCount == 0: return
        default: await runCatchUp()
        }
    }

    func runCatchUp() async {
        guard !catchUp.isLoading else { return }
        catchUp = .loading
        do {
            let response = try await TLDRAPI.catchUp(chat: chat.id)
            if let error = response.error {
                catchUp = .failed(error)
                return
            }
            catchUp = .done(response)
            // Caught up through the newest message the brief read.
            markRead(at: response.untilDate)
        } catch {
            catchUp = .failed(AIErrors.message(for: error))
        }
    }

    func ask(_ question: String) async {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !answer.isLoading else { return }
        lastQuestion = q
        answer = .loading
        do {
            let response = try await TLDRAPI.ask(chat: chat.id, question: String(q.prefix(500)))
            if let error = response.error {
                answer = .failed(error)
            } else {
                answer = .done(response)
            }
        } catch {
            answer = .failed(AIErrors.message(for: error))
        }
    }

    // MARK: - Lookups

    func name(of user: UUID) -> String {
        user == myId ? "You" : (names[user] ?? "Someone")
    }

    /// Sender and opening words of a message, for ref chips.
    func preview(_ id: UUID) -> (name: String, text: String)? {
        guard let m = messages.first(where: { $0.id == id }) else { return nil }
        let text = m.body.replacingOccurrences(of: "\n", with: " ")
        return (name(of: m.sender), text.count > 28 ? String(text.prefix(28)) + "…" : text)
    }
}
