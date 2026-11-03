//
//  SavedCatchUps.swift
//  Ketchup
//
//  Catch-ups and answers kept on the phone (Store/SavedBriefs.swift), to
//  read again with no network call:
//    - SavedBriefsSheet: one chat's "Earlier catch-ups", newest first, each
//      with its time and message count. Open one to read it; its sources
//      jump to the message when the chat has it loaded, and otherwise show
//      the message as it was kept. Swipe or long-press to delete one, or
//      Clear all.
//    - SavedCatchUpsView: every chat's, pushed from Settings' "Saved
//      catch-ups" row (SavedCatchUpsRow), next to its "Clear cache" row
//      (ClearCacheRow).
//

import SwiftUI

// MARK: - One chat

struct SavedBriefsSheet: View {
    let place: SavedPlace
    /// The chat's or the site's name, as the running head.
    let title: String
    var store: DeviceStore = .shared
    /// The open chat's own messages, when it has them loaded.
    var livePreview: ((UUID) -> (name: String, text: String)?)? = nil
    /// Closes the sheet and scrolls the chat to a message it has loaded.
    var jump: ((UUID) -> Void)? = nil
    /// Opens straight onto this one (from the all-chats list).
    var opening: UUID? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppModel.self) private var app: AppModel?
    @State private var briefs: [SavedBrief] = []
    @State private var open: SavedBrief?
    @State private var quote: SavedQuote?
    @State private var confirmClear = false
    @State private var scrolled = false

    var body: some View {
        ZStack {
            if let open {
                page(open)
                    .transition(.rise(reduceMotion: reduceMotion))
            } else {
                list
                    .transition(.opacity)
            }
        }
        .motion(Motion.settle, value: open?.id)
        .safeAreaInset(edge: .top, spacing: 0) {
            SheetBar(title: title, scrolled: scrolled) { dismiss() }
        }
        .background(Theme.cream)
        .presentationBackground(Theme.cream)
        .presentationDragIndicator(.visible)
        .onAppear {
            briefs = store.saved(place)?.briefs ?? []
            if let opening { open = briefs.first { $0.id == opening } }
        }
        .sheet(item: $quote) { SavedQuoteCard(quote: $0) }
        .confirmationDialog(clearTitle, isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Delete all", role: .destructive) {
                store.forgetAll(in: place)
                briefs = []
            }
        } message: {
            Text("They're only on this phone, so they can't come back.")
        }
    }

    // MARK: The list

    private var list: some View {
        List {
            VStack(alignment: .leading, spacing: 6) {
                Text("Earlier catch-ups")
                    .font(.serif(.largeTitle))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("Kept on this phone until you delete them, newest first.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSoft)
            }
            .savedRow(top: 14, bottom: 10)
            ForEach(briefs) { brief in
                Button { open = brief } label: {
                    SavedBriefRow(brief: brief, showsTitle: place.isWeb)
                }
                .buttonStyle(.pressable)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) { delete(brief) } label: { Label("Delete", systemImage: "trash") }
                }
                .contextMenu {
                    Button("Delete", systemImage: "trash", role: .destructive) { delete(brief) }
                }
                .savedRow(top: 5, bottom: 5)
            }
            if briefs.count > 1 {
                Button("Clear all") { confirmClear = true }
                    .buttonStyle(.outline(.compact))
                    .frame(maxWidth: .infinity)
                    .savedRow(top: 18, bottom: 30)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > 1
        } action: { _, isScrolled in
            scrolled = isScrolled
        }
        .overlay {
            if briefs.isEmpty { SavedEmpty() }
        }
    }

    private var clearTitle: String {
        briefs.count == 1 ? "Delete 1 saved catch-up?" : "Delete all \(briefs.count) saved catch-ups?"
    }

    private func delete(_ brief: SavedBrief) {
        store.forget(brief.id, in: place)
        briefs.removeAll { $0.id == brief.id }
        if open?.id == brief.id { open = nil }
    }

    // MARK: One of them

    private func page(_ brief: SavedBrief) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Button { open = nil } label: {
                    Label("Earlier catch-ups", systemImage: "chevron.backward")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ketchupText)
                }
                .buttonStyle(.pressable)
                if let catchUp = brief.catchUp {
                    CatchUpContent(brief: catchUp, byline: brief.byline, chatName: brief.title ?? title,
                                   readerName: readerName, refs: refs(for: brief))
                } else if let answer = brief.answer {
                    AnswerCard(question: brief.question ?? "", answer: answer, byline: brief.byline, refs: refs(for: brief))
                }
                Button("Delete from this phone") { delete(brief) }
                    .buttonStyle(.outline(.compact))
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 40)
        }
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > 1
        } action: { _, isScrolled in
            scrolled = isScrolled
        }
    }

    /// Sources read from the chat when it has the message loaded, and jump
    /// there; otherwise they read as kept, and open whole.
    private func refs(for brief: SavedBrief) -> RefContext {
        let live = livePreview
        return RefContext(
            preview: { id in
                live?(id) ?? brief.quote(id).map { ($0.name, SavedQuote.opening($0.text)) }
            },
            jump: { id in
                if let jump, live?(id) != nil || brief.quote(id) == nil {
                    jump(id)
                } else if let saved = brief.quote(id) {
                    quote = saved
                }
            },
            hint: jump == nil ? "Shows the whole message" : "Shows it in the chat")
    }

    /// The reader as the chat names them, for "You" in owes and questions.
    private var readerName: String {
        app?.me?.displayName ?? ""
    }
}

// MARK: - Every chat

/// Every chat's saved catch-ups, the most recent chat first, with the room
/// they take and Delete all. Pushed from Settings.
struct SavedCatchUpsView: View {
    var store: DeviceStore = .shared

    @State private var groups: [SavedGroup] = []
    @State private var bytes: Int?
    @State private var opened: Opened?
    @State private var confirmDelete = false

    private struct SavedGroup: Identifiable {
        let place: SavedPlace
        let chat: SavedChat
        var id: String { place.file }
    }

    private struct Opened: Identifiable {
        let place: SavedPlace
        let name: String
        let brief: UUID
        var id: UUID { brief }
    }

    var body: some View {
        List {
            Text("Every catch-up you've opened and every answer you got, kept on this phone until you delete them.")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSoft)
                .savedRow(top: 12, bottom: 6)
            if groups.isEmpty {
                SavedEmpty(compact: true)
                    .savedRow(top: 30, bottom: 10)
            }
            ForEach(groups) { group in
                Kicker(group.chat.name)
                    .accessibilityAddTraits(.isHeader)
                    .savedRow(top: 18, bottom: 2)
                ForEach(group.chat.briefs) { brief in
                    Button {
                        opened = Opened(place: group.place, name: group.chat.name, brief: brief.id)
                    } label: {
                        SavedBriefRow(brief: brief, showsTitle: group.place.isWeb)
                    }
                    .buttonStyle(.pressable)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) { delete(brief, in: group.place) } label: { Label("Delete", systemImage: "trash") }
                    }
                    .contextMenu {
                        Button("Delete", systemImage: "trash", role: .destructive) { delete(brief, in: group.place) }
                    }
                    .savedRow(top: 5, bottom: 5)
                }
            }
            if !groups.isEmpty {
                deleteAll
                    .savedRow(top: 26, bottom: 30)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.cream)
        .navigationTitle("Saved catch-ups")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Saved catch-ups")
                    .font(.serif(.headline))
                    .foregroundStyle(Theme.ink)
            }
        }
        .task { await reload() }
        .sheet(item: $opened, onDismiss: { Task { await reload() } }) { opened in
            SavedBriefsSheet(place: opened.place, title: opened.name, store: store, opening: opened.brief)
        }
        .confirmationDialog("Delete every saved catch-up?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete all", role: .destructive) {
                store.forgetAllSaved()
                Task { await reload() }
            }
        } message: {
            Text("They're only on this phone, so they can't come back.")
        }
    }

    /// How much room they take, and Delete all.
    private var deleteAll: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("On this phone")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Text(bytes.map(ByteSize.text) ?? " ")
                    .font(.mono(.caption))
                    .foregroundStyle(Theme.inkSoft)
            }
            Spacer(minLength: 8)
            Button("Delete all") { confirmDelete = true }
                .buttonStyle(.outline(.compact))
        }
        .paperCard(padding: 18)
    }

    private func delete(_ brief: SavedBrief, in place: SavedPlace) {
        store.forget(brief.id, in: place)
        Task { await reload() }
    }

    private func reload() async {
        groups = store.allSaved().map { SavedGroup(place: $0.place, chat: $0.chat) }
        bytes = await store.usage().saved
    }
}

// MARK: - Settings rows

/// Settings' "Saved catch-ups": how many there are, and the list.
struct SavedCatchUpsRow: View {
    @State private var count: Int?

    var body: some View {
        NavigationLink {
            SavedCatchUpsView()
        } label: {
            SettingsRow("Saved catch-ups", systemImage: "clock.arrow.circlepath",
                        value: count.map { $0 == 0 ? "None" : $0.formatted() }, chevron: true)
        }
        .buttonStyle(.pressable)
        .onAppear {
            count = DeviceStore.shared.allSaved().reduce(0) { $0 + $1.chat.briefs.count }
        }
    }
}

/// Settings' "Clear cache": the copy of your chats (DeviceStore) and the
/// photo cache (RemoteImages). Both load again from the server; saved
/// catch-ups stay.
struct ClearCacheRow: View {
    @State private var bytes: Int?
    @State private var confirming = false

    var body: some View {
        Button { confirming = true } label: {
            SettingsRow("Clear cache", systemImage: "arrow.counterclockwise", detail: detail)
        }
        .buttonStyle(.pressable)
        .disabled(bytes == 0)
        .task { await measure() }
        .confirmationDialog("Clear the cache?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Clear cache", role: .destructive) {
                DeviceStore.shared.clearCopies()
                RemoteImages.shared.clear()
                Task { await measure() }
            }
        } message: {
            Text("Your chats and photos load from the server again next time. Saved catch-ups stay.")
        }
    }

    /// "4.2 MB: your inbox, recent messages and photos."
    private var detail: String {
        let what = "your inbox, recent messages and photos. Saved catch-ups stay."
        switch bytes {
        case 0: return "Nothing to clear right now."
        case let bytes?: return "\(ByteSize.text(bytes)): \(what)"
        case nil: return what.prefix(1).uppercased() + what.dropFirst()
        }
    }

    private func measure() async {
        let photos = await Task.detached(priority: .utility) { RemoteImages.shared.diskBytes() }.value
        bytes = await DeviceStore.shared.usage().copies + photos
    }
}

nonisolated enum ByteSize {
    /// "312 KB", "4.2 MB".
    static func text(_ bytes: Int) -> String {
        Int64(bytes).formatted(.byteCount(style: .file))
    }
}

// MARK: - Pieces

/// A saved catch-up or answer in a list: what it was and when, the gist or
/// the question, and how many messages it read.
struct SavedBriefRow: View {
    let brief: SavedBrief
    /// A web chat's thread name, since one site's list mixes threads.
    var showsTitle = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Kicker("\(brief.kind == .catchUp ? "Catch-up" : "Asked") · \(brief.savedAt.savedStamp)")
            Text(verbatim: headline)
                .font(.serif(.headline, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(verbatim: details)
                .font(.mono(.caption))
                .foregroundStyle(Theme.inkSoft)
                .lineLimit(1)
        }
        .paperCard(padding: 16)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens it")
    }

    private var headline: String {
        if brief.kind == .ask { return "“\(brief.question ?? "")”" }
        return Sentences.first(brief.catchUp?.tldr ?? "").first
    }

    private var details: String {
        let count = brief.messageCount == 1 ? "1 message" : "\(brief.messageCount.formatted()) messages"
        guard showsTitle, let title = brief.title else { return count }
        return "\(title) · \(count)"
    }
}

/// No saved catch-ups yet.
private struct SavedEmpty: View {
    var compact = false

    var body: some View {
        VStack(spacing: 12) {
            if !compact {
                ZStack {
                    KetchupDrop().fill(Theme.ketchup)
                    DropShine().fill(Theme.onKetchup.opacity(0.9))
                }
                .frame(width: 56, height: 56)
                .padding(.bottom, 4)
                .accessibilityHidden(true)
            }
            Text("Nothing saved yet")
                .font(.serif(.title2))
                .foregroundStyle(Theme.ink)
            Text("Catch-ups you open and answers you get are kept here, on this phone, so you can read them again. Even offline.")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSoft)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
    }
}

/// A source as it was kept: who said it, in their chat color, and what
/// they said.
struct SavedQuoteCard: View {
    let quote: SavedQuote

    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .headline) private var avatar: CGFloat = 32

    private var text: some View {
        Text(verbatim: quote.text)
            .font(.body)
            .foregroundStyle(Theme.ink)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Monogram(name: quote.name, color: RefChip.color(for: quote.name), size: avatar)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: quote.name)
                        .font(.headline)
                        .foregroundStyle(RefChip.color(for: quote.name))
                    if let at = quote.at {
                        Text(at.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
                            .font(.mono(.caption))
                            .foregroundStyle(Theme.inkSoft)
                    }
                }
                Spacer(minLength: 8)
                Button("Done") { dismiss() }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .buttonStyle(.pressable)
            }
            ViewThatFits(in: .vertical) {
                text
                ScrollView { text }
            }
            Text("Kept on this phone with the catch-up.")
                .font(.footnote)
                .foregroundStyle(Theme.inkSoft)
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.cream)
        .presentationDetents([.fraction(0.35), .medium])
        .presentationBackground(Theme.cream)
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Helpers

extension SavedPlace {
    var isWeb: Bool { if case .web = self { true } else { false } }
}

extension SavedQuote {
    /// How a source chip starts: "so the Airbnb is now $540…".
    static func opening(_ text: String) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        return flat.count > 28 ? String(flat.prefix(28)) + "…" : flat
    }
}

extension SavedBrief {
    /// After "Read by Muse Spark": "302 messages", "Saved Nov 3, 4:12 PM".
    var byline: [String] {
        let count = messageCount == 1 ? "1 message" : "\(messageCount.formatted()) messages"
        return [count, "Saved \(savedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()))"]
    }
}

extension Date {
    /// "Today 4:12 PM", "Yesterday 9:30 PM", "Mon 9:30 AM", "Oct 28, 9:30 AM".
    var savedStamp: String {
        let time = formatted(date: .omitted, time: .shortened)
        let cal = Calendar.current
        if cal.isDateInToday(self) { return "Today \(time)" }
        if cal.isDateInYesterday(self) { return "Yesterday \(time)" }
        if let days = cal.dateComponents([.day], from: self, to: .now).day, days < 7 {
            return "\(formatted(.dateTime.weekday(.abbreviated))) \(time)"
        }
        return "\(formatted(.dateTime.month(.abbreviated).day())), \(time)"
    }
}

private extension View {
    /// A List row that's just paper on cream: no separator, no background.
    func savedRow(top: CGFloat, bottom: CGFloat) -> some View {
        self
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: top, leading: 20, bottom: bottom, trailing: 20))
    }
}
