//
//  SavedBriefs.swift
//  Ketchup
//
//  Catch-ups and Ask answers kept on the phone, so you can read them again
//  later with no network call: each chat's, newest first, and the
//  Instagram and Snapchat ones too (those never touch Ketchup's server).
//  Each keeps the messages it cites, as they were, so its sources still
//  read when the chat isn't loaded or isn't in Ketchup at all.
//
//  DeviceStore writes them (saved/<chat>.json) with the same protection as
//  the rest: complete until first unlock, out of backups, and gone at sign
//  out. They stay until you delete them, even after you leave the chat.
//

import Foundation

/// Where a saved catch-up came from.
enum SavedPlace: Hashable {
    /// One of Ketchup's own chats.
    case chat(UUID)
    /// A web chat source ("instagram", "snapchat"); its items name their thread.
    case web(String)

    var file: String {
        switch self {
        case .chat(let id): "\(id.uuidString.lowercased()).json"
        case .web(let source): "web-\(source).json"
        }
    }

    init?(file: String) {
        guard file.hasSuffix(".json") else { return nil }
        let name = String(file.dropLast(5))
        if name.hasPrefix("web-") {
            self = .web(String(name.dropFirst(4)))
        } else if let id = UUID(uuidString: name) {
            self = .chat(id)
        } else {
            return nil
        }
    }
}

/// A message a saved catch-up cites, as it was when it was kept.
struct SavedQuote: Codable, Equatable, Identifiable {
    /// The ref: a message id, or a web thread's index ref.
    let id: UUID
    /// "You" for the reader.
    let name: String
    let text: String
    /// When it was sent (about, for a web chat).
    var at: Date?
}

/// One catch-up or answer, kept to read again.
struct SavedBrief: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case catchUp, ask }

    /// The server's brief id when there is one, so a catch-up opened twice
    /// is kept once.
    let id: UUID
    let kind: Kind
    let savedAt: Date
    /// Messages Muse Spark read for it.
    let messageCount: Int
    /// A web chat's thread name; nil for Ketchup's own chats.
    var title: String?
    var catchUp: CatchUp?
    var question: String?
    var answer: ChatAnswer?
    var quotes: [SavedQuote]

    /// A finished catch-up, or nil for "nothing new".
    init?(catchUp response: BriefResponse<CatchUp>, title: String? = nil, quote: (UUID) -> SavedQuote?) {
        guard let brief = response.result else { return nil }
        self.init(id: response.briefId ?? UUID(), kind: .catchUp, savedAt: .now,
                  messageCount: response.messageCount ?? 0, title: title, catchUp: brief,
                  quotes: brief.allRefs.compactMap(quote))
    }

    /// An answer to `question`.
    init?(question: String, answer response: BriefResponse<ChatAnswer>, title: String? = nil,
          quote: (UUID) -> SavedQuote?) {
        guard let answer = response.result else { return nil }
        self.init(id: response.briefId ?? UUID(), kind: .ask, savedAt: .now,
                  messageCount: response.messageCount ?? 0, title: title, question: question, answer: answer,
                  quotes: answer.refs.compactMap(quote))
    }

    init(id: UUID, kind: Kind, savedAt: Date, messageCount: Int, title: String? = nil,
         catchUp: CatchUp? = nil, question: String? = nil, answer: ChatAnswer? = nil, quotes: [SavedQuote]) {
        self.id = id
        self.kind = kind
        self.savedAt = savedAt
        self.messageCount = messageCount
        self.title = title
        self.catchUp = catchUp
        self.question = question
        self.answer = answer
        self.quotes = quotes
    }

    func quote(_ ref: UUID) -> SavedQuote? {
        quotes.first { $0.id == ref }
    }
}

/// A chat's saved catch-ups and answers, newest first.
struct SavedChat: Codable, Equatable {
    /// The chat's name when something was last kept, for lists outside it.
    var name: String
    var briefs: [SavedBrief]
}

extension CatchUp {
    /// Every message it cites, once, in the order they first show up.
    var allRefs: [UUID] {
        let all = forYou.flatMap(\.refs) + plans.flatMap(\.refs) + owes.flatMap(\.refs)
            + openQuestions.flatMap(\.refs) + highlights.flatMap(\.refs)
        var seen = Set<UUID>()
        return all.filter { seen.insert($0).inserted }
    }
}

// MARK: - Keeping them

extension ChatModel {
    /// Keeps a catch-up the reader has seen, and the messages it cites.
    func keepOnPhone(_ response: BriefResponse<CatchUp>) {
        guard !isPreview, let saved = SavedBrief(catchUp: response, quote: savedQuote) else { return }
        DeviceStore.shared.keep(saved, in: .chat(chat.id), name: chat.name)
    }

    /// Keeps an answer, and the messages it cites.
    func keepOnPhone(_ response: BriefResponse<ChatAnswer>, question: String) {
        guard !isPreview, let saved = SavedBrief(question: question, answer: response, quote: savedQuote) else { return }
        DeviceStore.shared.keep(saved, in: .chat(chat.id), name: chat.name)
    }

    private func savedQuote(_ ref: UUID) -> SavedQuote? {
        guard let m = messages.first(where: { $0.id == ref }) else { return nil }
        return SavedQuote(id: ref, name: name(of: m.sender), text: m.body, at: m.createdAt)
    }
}

extension WebCatchUp {
    /// Keeps a web chat's catch-up on the phone only, with the thread's name
    /// and the messages it cites.
    func keepOnPhone(_ response: BriefResponse<CatchUp>) {
        guard !isPreviewThread, let saved = SavedBrief(catchUp: response, title: thread.displayTitle, quote: savedQuote) else { return }
        DeviceStore.shared.keep(saved, in: .web(thread.source.id), name: thread.source.name)
    }

    func keepOnPhone(_ response: BriefResponse<ChatAnswer>, question: String) {
        guard !isPreviewThread,
              let saved = SavedBrief(question: question, answer: response, title: thread.displayTitle, quote: savedQuote) else { return }
        DeviceStore.shared.keep(saved, in: .web(thread.source.id), name: thread.source.name)
    }

    private func savedQuote(_ ref: UUID) -> SavedQuote? {
        guard let m = thread.message(ref) else { return nil }
        return SavedQuote(id: ref, name: m.isMe ? "You" : m.sender, text: m.text, at: m.at.flatMap(JSON.date(from:)))
    }

    /// Offline previews (`-screen web-…`) aren't kept.
    private var isPreviewThread: Bool {
        #if DEBUG
        if PreviewData.isActive { return true }
        #endif
        return false
    }
}
