//
//  ChatModel.swift
//  Ketchup
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
//  summarizes everything after the server-side cursor, so moving it on
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
    /// Your read cursor when the chat opened: the inbox row's, then the
    /// server's (your member row) once open() has it.
    private var cursorAtOpen: Date
    /// What you've read through on this phone since (a send, a catch-up,
    /// scrolling to the bottom), ahead of the server's cursor catching up.
    /// Unread counts from whichever is later, so a first page or member row
    /// that answers after you sent can't bring the unread count back.
    private var readThrough: Date?
    /// True once the bottom of the thread has been on screen.
    var sawBottom = false

    // Muse Spark
    private(set) var catchUp: AIPhase<BriefResponse<CatchUp>> = .idle
    private(set) var answer: AIPhase<BriefResponse<ChatAnswer>> = .idle
    private(set) var lastQuestion = ""

    private static let pageSize = 200
    /// The edge function reads at most 600 unread; PostgREST serves up to 1000 rows.
    private static let maxFirstLoad = 700
    /// Unread count that triggers a background catch-up on open.
    private static let prefetchAt = 15
    /// Set once the user has asked for the catch-up (tapped the button).
    private var userAsked = false
    /// A prefetched catch-up nobody has opened yet: the cursor moves to this
    /// only when the user actually looks at it.
    private var unseenBrief = false
    private var unseenUntil: Date?

    /// Messages from the copy the phone kept (DeviceStore), until the
    /// server's first page replaces them.
    private var keptIds: Set<UUID> = []
    /// The server's first page is in, with the unread count from your
    /// member row: what's on screen is the server's now, not the phone's.
    private(set) var synced = false
    private var opening = false
    private var prefetched = false

    /// Offline preview mode (DEBUG only, see Debug/PreviewData.swift): the
    /// network calls below are skipped and Muse Spark answers are canned.
    private(set) var isPreview = false
    #if DEBUG
    @ObservationIgnored private var script = PreviewScript()
    #endif

    @ObservationIgnored
    lazy var realtime = ChatRealtime(chatId: chat.id) { [weak self] message in
        self?.merge([message])
    }

    init(chat: ChatSummary, myId: UUID) {
        self.chat = chat
        self.myId = myId
        self.unreadCount = chat.unreadCount
        self.cursorAtOpen = chat.lastReadAt
        restoreFromDevice()
    }

    // MARK: - Loading

    func open() async {
        #if DEBUG
        if isPreview {
            openPreview()
            return
        }
        #endif
        realtime.start()
        guard !synced, !opening else { return }
        opening = true
        defer { opening = false }
        var paged = false
        do {
            // Reach back past the first unread message (plus a little context),
            // so the "N new messages" divider lands where the unread part starts.
            let limit = min(max(Self.pageSize, unreadCount + 25), Self.maxFirstLoad)
            let page = try await KetchupAPI.messages(in: chat.id, limit: limit)
            // The server's page replaces the copy the phone kept.
            messages = ThreadSnapshot.reconcile(messages, kept: keptIds, page: page)
            keptIds = []
            hasOlder = page.count >= limit
            merge(page)
            loaded = true
            paged = true
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
        var exact = false
        if await loadMembers(), paged { exact = await readFromServerCursor() }
        computeUnread(exact: exact)
        if paged { synced = true }
        keepOnDevice()
        // A big backlog: start Muse Spark now so the tap feels instant. Once:
        // poll() runs open() again until the first page is in.
        if !prefetched, unreadCount >= Self.prefetchAt {
            prefetched = true
            Task { await runCatchUp(prefetch: true) }
        }
    }

    func close() {
        realtime.stop()
        if sawBottom { markRead() }
        keepOnDevice()
    }

    @discardableResult
    func loadMembers() async -> Bool {
        guard !isPreview, let list = try? await KetchupAPI.members(of: chat.id) else { return false }
        members = list
        for m in list { names[m.userId] = m.name }
        return true
    }

    /// The inbox row this chat opened from can be the phone's copy from
    /// last time; your member row is the server's word on where you've read
    /// to. Takes that cursor and pages back until the unread part is all
    /// here. True when it is, so the unread count can be exact.
    private func readFromServerCursor() async -> Bool {
        guard let mine = members.first(where: { $0.userId == myId }) else { return false }
        cursorAtOpen = mine.lastReadAt
        while hasOlder, messages.count < Self.maxFirstLoad,
              let oldest = messages.first(where: { !$0.pending && !$0.failed }), oldest.createdAt > cursorAtOpen {
            let before = messages.count
            await loadOlder()
            if messages.count == before { break }
        }
        return !hasOlder || (messages.first.map { $0.createdAt <= cursorAtOpen } ?? true)
    }

    func loadOlder() async {
        guard !isPreview, hasOlder, !loadingOlder, let oldest = messages.first(where: { !$0.pending && !$0.failed }) else { return }
        loadingOlder = true
        defer { loadingOlder = false }
        guard let page = try? await KetchupAPI.messages(in: chat.id, before: oldest.createdAt, limit: Self.pageSize) else { return }
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
    /// Until the first page is in (opened offline on the kept copy), it
    /// tries that page again instead.
    func poll() async {
        guard !isPreview else { return }
        guard synced else { return await open() }
        let newest = messages.last(where: { !$0.pending && !$0.failed })?.createdAt ?? chat.createdAt
        guard let fresh = try? await KetchupAPI.messages(in: chat.id, after: newest) else { return }
        merge(fresh)
    }

    /// `exact`: everything after the server's cursor is loaded, so the count
    /// is what's here, not at least the inbox row's.
    private func computeUnread(exact: Bool = false) {
        let cursor = max(cursorAtOpen, readThrough ?? .distantPast)
        let unread = messages.filter { $0.createdAt > cursor && $0.sender != myId && !$0.pending }
        firstUnreadId = unread.first?.id
        unreadCount = exact ? unread.count : max(unreadCount, unread.count)
        if unreadCount == 0 { firstUnreadId = nil }
        unreadAtOpen = unreadCount
    }

    // MARK: - Kept on the phone

    /// Opens on the copy of this chat the phone kept from last time
    /// (DeviceStore), before the server answers. "Load earlier" waits for
    /// the server's page.
    private func restoreFromDevice() {
        guard let kept = DeviceStore.shared.thread(chat.id) else { return }
        messages = kept.messages
        members = kept.members
        for m in kept.members { names[m.userId] = m.name }
        keptIds = Set(kept.messages.map(\.id))
        loaded = true
        computeUnread()
    }

    /// The phone's copy already reaches the inbox row's last message, so
    /// the thread can be placed before the server answers.
    var showsCurrentCopy: Bool {
        guard let newest = messages.last(where: { keptIds.contains($0.id) }) else { return false }
        return newest.createdAt >= (chat.lastMessageAt ?? .distantPast)
    }

    private func keepOnDevice() {
        guard synced, !isPreview else { return }
        DeviceStore.shared.saveThread(chat.id, messages: messages, members: members)
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

    /// A photo, with a caption or none. The bubble shows it at once from the
    /// image cache; its files upload before the row goes in (Photos/ChatPhotos.swift).
    func send(_ photo: PreparedPhoto, caption: String) {
        let id = UUID()
        let message = Message(id: id, chatId: chat.id, sender: myId, body: caption, createdAt: .now, pending: true,
                              imagePath: ChatPhotos.path(chat: chat.id, message: id),
                              imageWidth: photo.width, imageHeight: photo.height)
        PhotoUploads.shared.hold(photo, for: message)
        messages.append(message)
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
            let row = try await post(local)
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

    /// The insert, after a photo's upload. An offline preview confirms the bubble itself.
    private func post(_ message: Message) async throws -> Message {
        if message.imagePath != nil {
            try await PhotoUploads.shared.upload(for: message, previewing: isPreview)
        }
        #if DEBUG
        if isPreview {
            try await Task.sleep(for: .milliseconds(400))
            PhotoUploads.shared.finished(message.id)
            return message
        }
        #endif
        let image = message.imagePath.map { (path: $0, width: message.imageWidth ?? 1, height: message.imageHeight ?? 1) }
        let row = try await KetchupAPI.send(id: message.id, chat: chat.id, body: message.body, image: image)
        PhotoUploads.shared.finished(message.id)
        return row
    }

    // MARK: - Read cursor

    /// The user scrolled down to the bottom themselves.
    func reachedBottomByScrolling() {
        sawBottom = true
        if unreadCount > 0 { markRead() }
    }

    private func markRead(at date: Date? = nil) {
        caughtUp(through: date ?? .now)
        guard !isPreview else { return }
        let id = chat.id
        Task { try? await KetchupAPI.markRead(id, at: date) }
    }

    private func caughtUp(through date: Date = .now) {
        unreadCount = 0
        readThrough = max(readThrough ?? .distantPast, date)
    }

    // MARK: - Muse Spark

    /// Starts a catch-up unless one is running or a finished one still
    /// covers everything unread.
    func catchUpIfNeeded() async {
        userAsked = true
        switch catchUp {
        case .loading:
            return  // a prefetch is running; it marks read when it lands
        case .done(let response) where unseenBrief:
            markRead(at: unseenUntil)  // the prefetched brief is being read now
            unseenBrief = false
            keepOnPhone(response)
        case .done where unreadCount == 0:
            return
        default:
            await runCatchUp()
        }
    }

    /// `prefetch` runs it in the background on open; the read cursor waits
    /// until the user taps "Catch me up" and sees the result.
    func runCatchUp(prefetch: Bool = false) async {
        if !prefetch { userAsked = true }
        guard !catchUp.isLoading else { return }
        catchUp = .loading
        do {
            let response = try await fetchCatchUp()
            if let error = response.error {
                catchUp = .failed(error)
                return
            }
            catchUp = .done(response)
            // Caught up through the newest message the brief read.
            if userAsked {
                markRead(at: response.untilDate)
                keepOnPhone(response)
            } else {
                unseenBrief = true
                unseenUntil = response.untilDate
            }
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
            let response = try await fetchAnswer(String(q.prefix(500)))
            if let error = response.error {
                answer = .failed(error)
            } else {
                answer = .done(response)
                keepOnPhone(response, question: q)
            }
        } catch {
            answer = .failed(AIErrors.message(for: error))
        }
    }

    /// The two Muse Spark calls. An offline preview plays back canned results.
    private func fetchCatchUp() async throws -> BriefResponse<CatchUp> {
        #if DEBUG
        if isPreview { return try await script.catchUp.land(after: script.delay) }
        #endif
        return try await KetchupAPI.catchUp(chat: chat.id)
    }

    private func fetchAnswer(_ question: String) async throws -> BriefResponse<ChatAnswer> {
        #if DEBUG
        if isPreview { return try await script.answer.land(after: script.delay) }
        #endif
        return try await KetchupAPI.ask(chat: chat.id, question: question)
    }

    // MARK: - Lookups

    func name(of user: UUID) -> String {
        user == myId ? "You" : (names[user] ?? "Someone")
    }

    /// Sender and opening words of a message, for ref chips.
    func preview(_ id: UUID) -> (name: String, text: String)? {
        guard let m = messages.first(where: { $0.id == id }) else { return nil }
        let text = m.previewText.replacingOccurrences(of: "\n", with: " ")
        return (name(of: m.sender), text.count > 28 ? String(text.prefix(28)) + "…" : text)
    }
}

// MARK: - Offline preview

#if DEBUG
extension ChatModel {
    /// What the Muse Spark calls return in an offline preview, and how long
    /// they take.
    struct PreviewScript {
        var catchUp: AIPhase<BriefResponse<CatchUp>> = .loading
        var answer: AIPhase<BriefResponse<ChatAnswer>> = .loading
        var delay: Duration = .zero
        /// The thread never finishes loading (`-screen chat-loading`).
        var holdsLoading = false
    }

    /// An offline chat for `-screen` previews: these members and messages, no
    /// network, and Muse Spark requests that go to `.loading`, wait `delay`,
    /// then land on `catchUp` or `answer` (a canned `.loading` never lands).
    /// With `asked`, it opens as if that question was already answered.
    /// `loading` keeps the thread waiting on its first page.
    static func preview(chat: ChatSummary, myId: UUID, members: [Member], messages: [Message],
                        catchUp: AIPhase<BriefResponse<CatchUp>>,
                        answer: AIPhase<BriefResponse<ChatAnswer>>,
                        delay: Duration, asked question: String? = nil, loading: Bool = false) -> ChatModel {
        let model = ChatModel(chat: chat, myId: myId)
        model.isPreview = true
        model.script = PreviewScript(catchUp: catchUp, answer: answer, delay: delay, holdsLoading: loading)
        model.members = members
        for member in members { model.names[member.userId] = member.name }
        model.merge(messages)
        model.computeUnread()
        if let question {
            model.lastQuestion = question
            model.answer = answer
        }
        return model
    }

    /// The fixtures are already in, so do what a live open does after loading:
    /// count unread and prefetch a big backlog.
    private func openPreview() {
        guard !loaded, !script.holdsLoading else { return }
        loaded = true
        computeUnread()
        synced = true
        if unreadCount >= Self.prefetchAt {
            Task { await runCatchUp(prefetch: true) }
        }
    }
}

fileprivate extension AIPhase {
    /// Plays a canned phase back like a real request: waits `delay`, then
    /// returns the value or throws the failure. `.loading` (and `.idle`)
    /// never land, for the loading screenshot.
    func land(after delay: Duration) async throws -> Value {
        switch self {
        case .done(let value):
            try await Task.sleep(for: delay)
            return value
        case .failed(let message):
            try await Task.sleep(for: delay)
            throw APIError.server(message)
        case .idle, .loading:
            while true { try await Task.sleep(for: .seconds(3600)) }
        }
    }
}
#endif
