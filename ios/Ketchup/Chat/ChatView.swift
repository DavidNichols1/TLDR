//
//  ChatView.swift
//  Ketchup
//
//  One group chat: bubbles with sender names and day separators, the
//  pinned Muse Spark bar, and the sheets it opens. A ref chip in a sheet
//  closes it and scrolls here to the cited message, which glows briefly.
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

    private static let bottomId = "bottom"
    private static let unreadId = "unread-divider"

    enum ChatSheet: String, Identifiable {
        case catchUp, ask, info
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

    var body: some View {
        ScrollViewReader { proxy in
            thread
                .onChange(of: model.messages.last?.id) { _, _ in
                    guard positioned, let last = model.messages.last else { return }
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
                    await model.open()
                    await position(proxy)
                }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if model.loaded && !model.messages.isEmpty {
                CatchUpBar(unread: model.unreadCount,
                           hasBrief: model.catchUp.value != nil,
                           onCatchUp: { sheet = .catchUp },
                           onAsk: { sheet = .ask })
                    .background(.bar)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ChatInputBar(placeholder: "Message", text: $draft) {
                guard let text = ChatInputBar.sendable(draft) else { return }
                draft = ""
                model.send(text)
            }
        }
        .overlay(alignment: .bottom) { noticeToast }
        .navigationTitle(model.chat.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { sheet = .catchUp } label: { Label("Catch me up", systemImage: Theme.aiSymbol) }
                    Button { sheet = .ask } label: { Label("Ask the chat", systemImage: "questionmark.bubble") }
                    Divider()
                    Button { sheet = .info } label: { Label("Members & invite", systemImage: "person.2") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(item: $sheet, onDismiss: sheetDismissed) { which in
            switch which {
            case .catchUp:
                CatchUpSheet(model: model, refs: refContext)
            case .ask:
                AskSheet(model: model, refs: refContext)
            case .info:
                ChatInfoSheet(model: model) {
                    leftChat = true
                    sheet = nil
                }
            }
        }
        // While Realtime is down, poll every 4 s; when it comes back, one
        // poll fills whatever arrived during the gap.
        .task(id: model.realtime.isLive) {
            if model.realtime.isLive {
                await model.poll()
                return
            }
            while !Task.isCancelled {
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
                        if model.loadingOlder { ProgressView() } else { Text("Load earlier messages") }
                    }
                    .font(.footnote)
                    .padding(.vertical, 10)
                }
                ForEach(rows) { row in
                    rowView(row)
                        .id(row.id)
                }
                Color.clear.frame(height: 1).id(Self.bottomId)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
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
        .overlay { emptyState }
    }

    @ViewBuilder
    private var emptyState: some View {
        if !model.loaded, let error = model.loadError {
            ContentUnavailableView {
                Label("Couldn't load this chat", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error)
            } actions: {
                Button("Try again") { Task { await model.open() } }
            }
        } else if !model.loaded {
            ProgressView()
        } else if model.messages.isEmpty {
            ContentUnavailableView {
                Label("No messages yet", systemImage: "bubble.left.and.bubble.right")
            } description: {
                Text("Say hi, or share invite code \(model.chat.inviteCode) so friends can join.")
            }
        }
    }

    @ViewBuilder
    private func rowView(_ row: Row) -> some View {
        switch row {
        case .day(let day):
            ThreadDivider(text: day.daySeparator)
        case .unread(let count):
            ThreadDivider(text: count == 1 ? "1 new message" : "\(count) new messages", isUnread: true)
        case .message(let m, let newRun):
            let mine = m.sender == model.myId
            ChatBubble(text: m.body,
                       mine: mine,
                       pending: m.pending,
                       failed: m.failed,
                       senderName: newRun && !mine ? model.name(of: m.sender) : nil,
                       senderColor: Theme.personColor(m.sender),
                       time: m.createdAt,
                       highlighted: highlighted == m.id,
                       onRetry: { model.retry(m.id) })
                .padding(.top, newRun ? 8 : 2)
                .padding(.vertical, 2)
                .background {
                    if highlighted == m.id {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Theme.aiWash)
                            .padding(.horizontal, -8)
                    }
                }
        }
    }

    // MARK: - Rows

    private enum Row: Identifiable {
        case day(Date)
        case unread(Int)
        case message(Message, newRun: Bool)

        var id: String {
            switch self {
            case .day(let d): "day-\(Int(d.timeIntervalSince1970))"
            case .unread: ChatView.unreadId
            case .message(let m, _): m.id.uuidString
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
            out.append(.message(m, newRun: m.sender != lastSender))
            lastSender = m.sender
        }
        return out
    }

    // MARK: - Scrolling

    /// First stop: the "new messages" divider if there's anything unread
    /// (so the Catch me up button is still meaningful), else the bottom.
    private func position(_ proxy: ScrollViewProxy) async {
        guard !positioned else { return }
        try? await Task.sleep(for: .milliseconds(60))
        if model.firstUnreadId != nil {
            proxy.scrollTo(Self.unreadId, anchor: .top)
        } else {
            proxy.scrollTo(Self.bottomId, anchor: .bottom)
        }
        try? await Task.sleep(for: .milliseconds(350))
        positioned = true
        // A short thread fits on screen: the bottom is already visible and
        // won't "change" into view, so count it as seen now.
        if atBottom { model.sawBottom = true }
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
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.thinMaterial, in: Capsule())
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
