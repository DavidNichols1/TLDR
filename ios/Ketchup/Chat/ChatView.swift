//
//  ChatView.swift
//  Ketchup
//
//  One group chat: bubbles with sender names and day separators, the
//  pinned Muse Spark bar, and the sheets it opens. A ref chip in a sheet
//  closes it and scrolls here to the cited message, where a mustard marker
//  sweeps behind the bubble for a moment.
//
//  When and why the read cursor moves is explained at the top of
//  ChatModel.swift; this view only reports scrolling and leaving.
//

import SwiftUI

struct ChatView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var model: ChatModel
    @State private var draft = ""
    @State private var sheet: ChatSheet?
    /// Set by a ref chip; acted on once the sheet is gone.
    @State private var pendingJump: UUID?
    @State private var jumpRequest: UUID?
    @State private var highlighted: UUID?
    /// The user has dragged the thread (programmatic scrolls don't count).
    @State private var userScrolled = false
    @State private var atBottom = true
    /// The first scroll (to the unread divider or the bottom) is done.
    @State private var positioned = false
    @State private var leftChat = false
    @State private var notice: String?
    /// Photos: picking one, the one waiting to go, the one open full screen.
    @State private var pickingPhoto = false
    @State private var attachment: PreparedPhoto?
    @State private var viewing: Message?
    #if DEBUG
    /// Offline previews: a message to jump to once the thread is in place,
    /// as if a ref chip asked for it.
    @State private var previewJump: UUID?
    #endif

    private static let bottomId = "bottom"
    private static let unreadId = "unread-divider"

    @ScaledMetric(relativeTo: .body) private var avatarSize: CGFloat = 28

    enum ChatSheet: String, Identifiable {
        case catchUp, ask, saved, info
        var id: String { rawValue }
    }

    init(chat: ChatSummary, myId: UUID) {
        #if DEBUG
        // Offline preview mode: inbox → chat stays on fixtures.
        if let preview = PreviewData.chatModel(for: chat.id) {
            _model = State(initialValue: preview)
            return
        }
        #endif
        _model = State(initialValue: ChatModel(chat: chat, myId: myId))
    }

    /// A chat whose model was built elsewhere (the offline previews).
    init(model: ChatModel) {
        _model = State(initialValue: model)
    }

    #if DEBUG
    /// Offline preview that jumps to `message` after opening, like a ref chip.
    init(model: ChatModel, jumpingTo message: UUID) {
        _model = State(initialValue: model)
        _previewJump = State(initialValue: message)
    }

    /// Offline preview with a photo picked and waiting in the composer.
    init(model: ChatModel, attaching photo: PreparedPhoto?, caption: String = "") {
        _model = State(initialValue: model)
        _attachment = State(initialValue: photo)
        _draft = State(initialValue: caption)
    }
    #endif

    var body: some View {
        ScrollViewReader { proxy in
            thread
                .onChange(of: model.messages.last?.id) { _, _ in
                    guard let last = model.messages.last else { return }
                    // A bubble you just sent comes into view even before the first page is in.
                    guard positioned || (last.sender == model.myId && (last.pending || last.failed)) else { return }
                    if last.sender == model.myId || atBottom {
                        withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(Self.bottomId, anchor: .bottom) }
                    }
                }
                .onChange(of: jumpRequest) { _, id in
                    guard let id else { return }
                    jumpRequest = nil
                    Task { await jump(to: id, proxy: proxy) }
                }
                .task {
                    async let opened: Void = model.open()
                    // The copy the phone kept is already current: place it while the server answers.
                    if model.showsCurrentCopy { await place(proxy) }
                    await opened
                    if model.loaded, model.loadError != nil { show("Couldn't refresh. Showing saved messages.") }
                }
                // The server's page is in (now, or when a retry gets it).
                .onChange(of: model.synced) { _, synced in
                    if synced { Task { await position(proxy) } }
                }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if model.loaded && !model.messages.isEmpty {
                CatchUpBar(unread: model.unreadCount,
                           hasBrief: model.catchUp.value != nil,
                           onCatchUp: { sheet = .catchUp },
                           onAsk: { sheet = .ask })
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ChatInputBar(placeholder: attachment == nil ? "Message" : "Add a caption", text: $draft,
                         attachment: attachment?.preview,
                         onPhoto: { pickingPhoto = true },
                         onRemoveAttachment: { attachment = nil }) {
                if let photo = attachment {
                    guard let caption = ChatInputBar.caption(draft) else { return }
                    draft = ""
                    attachment = nil
                    model.send(photo, caption: caption)
                } else {
                    guard let text = ChatInputBar.sendable(draft) else { return }
                    draft = ""
                    model.send(text)
                }
            }
        }
        .chatPhotoPicker(isPresented: $pickingPhoto) { attachment = $0 }
        .fullScreenCover(item: $viewing) { message in
            PhotoViewer(message: message, senderName: model.name(of: message.sender))
        }
        .overlay(alignment: .bottom) { noticeToast }
        .navigationTitle(model.chat.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(model.chat.name)
                        .font(.serif(.headline))
                        .foregroundStyle(Theme.ink)
                    Text(peopleLine)
                        .font(.mono(.caption2))
                        .foregroundStyle(Theme.inkSoft)
                }
                .lineLimit(1)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { sheet = .catchUp } label: { Label("Catch me up", systemImage: "drop") }
                    Button { sheet = .ask } label: { Label("Ask the chat", systemImage: "questionmark.bubble") }
                    Button { sheet = .saved } label: { Label("Earlier catch-ups", systemImage: "clock.arrow.circlepath") }
                    Divider()
                    Button { sheet = .info } label: { Label("Members & invite", systemImage: "person.2") }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(Theme.ink)
                }
                .accessibilityLabel("Chat options")
            }
        }
        .sheet(item: $sheet, onDismiss: sheetDismissed) { which in
            switch which {
            case .catchUp:
                CatchUpSheet(model: model, refs: refContext)
            case .ask:
                AskSheet(model: model, refs: refContext)
            case .saved:
                SavedBriefsSheet(place: .chat(model.chat.id), title: model.chat.name,
                                 livePreview: { model.preview($0) }, jump: refContext.jump)
            case .info:
                ChatInfoSheet(model: model) {
                    leftChat = true
                    sheet = nil
                }
            }
        }
        // While Realtime is down, poll every 4 s; when it comes back, one
        // poll fills whatever arrived during the gap. Until the first page is
        // in (a chat opened offline), keep trying either way.
        .task(id: model.realtime.isLive) {
            if model.realtime.isLive { await model.poll() }
            while !Task.isCancelled, !model.realtime.isLive || !model.synced {
                try? await Task.sleep(for: .seconds(4))
                if Task.isCancelled { return }
                await model.poll()
            }
        }
        .onChange(of: model.unreadCount) { _, count in
            if count == 0 { app.markReadLocally(model.chat.id) }
        }
        .onDisappear { model.close() }
    }

    // MARK: - Thread

    @ViewBuilder
    private var thread: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if model.hasOlder {
                    Button {
                        Task { await model.loadOlder() }
                    } label: {
                        if model.loadingOlder {
                            ProgressView().tint(Theme.inkSoft)
                        } else {
                            Text("Load earlier messages")
                        }
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.ketchupText)
                    .padding(.vertical, 10)
                }
                ForEach(rows) { row in
                    rowView(row)
                        .id(row.id)
                }
                Color.clear.frame(height: 1).id(Self.bottomId)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .background(Theme.cream)
        .defaultScrollAnchor(.bottom)
        .scrollDismissesKeyboard(.interactively)
        .onScrollPhaseChange { _, phase in
            if phase == .interacting { userScrolled = true }
        }
        .onScrollGeometryChange(for: Bool.self) { geo in
            geo.visibleRect.maxY >= geo.contentSize.height - 40
        } action: { _, bottom in
            atBottom = bottom
            guard bottom, positioned else { return }
            if userScrolled {
                model.reachedBottomByScrolling()
            } else {
                model.sawBottom = true
            }
        }
        .overlay { ZStack { emptyState }.motion(Motion.fade, value: model.loaded) }
    }

    @ViewBuilder
    private var emptyState: some View {
        if !model.loaded, let error = model.loadError {
            ThreadNote(title: "Couldn't load this chat", message: Text(error)) {
                Button("Try again") { Task { await model.open() } }
                    .buttonStyle(.outline(.compact))
            }
        } else if !model.loaded {
            ThreadSkeleton()
        } else if model.messages.isEmpty {
            let code = Text(model.chat.inviteCode).font(.mono(.body, weight: .semibold)).foregroundStyle(Theme.ink)
            ThreadNote(title: "Quiet in here",
                       message: Text("Say hi, or share invite code \(code) so friends can join.")) {
                EmptyView()
            }
        }
    }

    private var peopleLine: String {
        let count = model.members.isEmpty ? model.chat.memberCount : model.members.count
        return count == 1 ? "1 person" : "\(count) people"
    }

    @ViewBuilder
    private func rowView(_ row: Row) -> some View {
        switch row {
        case .day(let day):
            ThreadDivider(text: day.daySeparator)
        case .unread(let count):
            UnreadDivider(count: count)
        case .message(let m, let newRun, let endsRun):
            let mine = m.sender == model.myId
            let name = model.name(of: m.sender)
            HStack(alignment: .bottom, spacing: 8) {
                // Other people's photos sit by the last bubble of each run.
                if !mine {
                    if endsRun {
                        Avatar(name: name, path: model.avatarPath(of: m.sender), size: avatarSize)
                    } else {
                        Color.clear.frame(width: avatarSize, height: 1)
                    }
                }
                if m.imagePath != nil {
                    PhotoBubble(message: m,
                                mine: mine,
                                senderName: newRun && !mine ? name : nil,
                                senderColor: Theme.personColor(name: name),
                                startsRun: newRun,
                                endsRun: endsRun,
                                highlighted: highlighted == m.id,
                                onOpen: { viewing = m },
                                onRetry: { model.retry(m.id) })
                } else {
                    ChatBubble(text: m.body,
                               mine: mine,
                               pending: m.pending,
                               failed: m.failed,
                               senderName: newRun && !mine ? name : nil,
                               senderColor: Theme.personColor(name: name),
                               time: m.createdAt,
                               startsRun: newRun,
                               endsRun: endsRun,
                               highlighted: highlighted == m.id,
                               onRetry: { model.retry(m.id) })
                }
            }
                .padding(.top, newRun ? 10 : 0)
                .padding(.vertical, 1.5)
                // Under its neighbors, so the jump mark stays behind every bubble.
                .zIndex(highlighted == m.id ? -1 : 0)
        }
    }

    // MARK: - Rows

    private enum Row: Identifiable {
        case day(Date)
        case unread(Int)
        /// `newRun`: first of a run from one sender; `endsRun`: last of it.
        case message(Message, newRun: Bool, endsRun: Bool)

        var id: String {
            switch self {
            case .day(let d): "day-\(Int(d.timeIntervalSince1970))"
            case .unread: ChatView.unreadId
            case .message(let m, _, _): m.id.uuidString
            }
        }
    }

    private var rows: [Row] {
        var out: [Row] = []
        var lastDay: Date?
        var lastSender: UUID?
        let cal = Calendar.current
        for m in model.messages {
            let day = cal.startOfDay(for: m.createdAt)
            if day != lastDay {
                out.append(.day(day))
                lastDay = day
                lastSender = nil
            }
            if m.id == model.firstUnreadId {
                out.append(.unread(model.unreadAtOpen))
                lastSender = nil
            }
            let continues = m.sender == lastSender
            // The bubble before this one is from the same sender, so its run goes on.
            if continues, case .message(let previous, let newRun, _)? = out.last {
                out[out.count - 1] = .message(previous, newRun: newRun, endsRun: false)
            }
            out.append(.message(m, newRun: !continues, endsRun: true))
            lastSender = m.sender
        }
        return out
    }

    // MARK: - Scrolling

    /// First stop, once the server's page is in: the "new messages" divider
    /// if there's anything unread (so the Catch me up button is still
    /// meaningful), else the bottom. Only then does what's on screen count
    /// as seen; a kept copy placed earlier can be out of date.
    private func position(_ proxy: ScrollViewProxy) async {
        guard !positioned else { return }
        await place(proxy)
        positioned = true
        // A short thread fits on screen: the bottom is already visible and
        // won't "change" into view, so count it as seen now.
        if atBottom, !userScrolled { model.sawBottom = true }
        #if DEBUG
        if let id = previewJump {
            previewJump = nil
            jumpRequest = id
        }
        #endif
    }

    /// Scrolls to the divider or the bottom, unless they've started scrolling
    /// themselves (the kept copy while the server answered): leave them be.
    private func place(_ proxy: ScrollViewProxy) async {
        try? await Task.sleep(for: .milliseconds(60))
        guard !userScrolled else { return }
        if model.firstUnreadId != nil {
            proxy.scrollTo(Self.unreadId, anchor: .top)
        } else {
            proxy.scrollTo(Self.bottomId, anchor: .bottom)
        }
        try? await Task.sleep(for: .milliseconds(350))
    }

    private func jump(to id: UUID, proxy: ScrollViewProxy) async {
        guard await model.ensureLoaded(id) else {
            show("That message is too far back to show.")
            return
        }
        try? await Task.sleep(for: .milliseconds(80))
        withAnimation(.easeInOut(duration: 0.45)) {
            proxy.scrollTo(id.uuidString, anchor: .center)
        }
        try? await Task.sleep(for: .milliseconds(380))
        highlighted = id
        try? await Task.sleep(for: .seconds(1.8))
        if highlighted == id {
            withAnimation(.easeOut(duration: 0.4)) { highlighted = nil }
        }
    }

    private var refContext: RefContext {
        RefContext(preview: { model.preview($0) },
                   jump: { id in
                       pendingJump = id
                       sheet = nil
                   })
    }

    private func sheetDismissed() {
        if leftChat {
            Task { await app.refreshChats() }
            dismiss()
            return
        }
        if let id = pendingJump {
            pendingJump = nil
            jumpRequest = id
        }
    }

    // MARK: - Notice

    @ViewBuilder
    private var noticeToast: some View {
        if let notice {
            Text(notice)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.onInk)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Theme.ink, in: Capsule())
                .padding(.bottom, 70)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func show(_ text: String) {
        withAnimation { notice = text }
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation { if notice == text { notice = nil } }
        }
    }
}

/// What the thread says when there's nothing to show: a serif line, a
/// sentence, and maybe a button.
private struct ThreadNote<Actions: View>: View {
    let title: String
    let message: Text
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.serif(.title3))
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            message
                .font(.body)
                .foregroundStyle(Theme.inkSoft)
            actions
                .padding(.top, 4)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 40)
    }
}
