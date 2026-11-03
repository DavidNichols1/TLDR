//
//  JoinedPreview.swift
//  Ketchup
//
//  `-screen chat-joined`: the end of the Breck thread, read through Maya's
//  "goodnight losers 💙", then Rowan (made up, a friend of Maya's) joins
//  with the invite code and says hi. The thread shows "Rowan joined" under
//  the "1 new" line: a join line starts the new part but isn't counted.
//

#if DEBUG
import Foundation

extension PreviewData {
    static let rowan = UUID(uuidString: "D0000000-0000-4000-8000-000000000007")!

    static func joinedChatModel() -> ChatModel {
        let readTo = messages.last?.createdAt ?? breck.createdAt
        let joined = Message(id: UUID(uuidString: "F0000000-0000-4000-8000-000000000001")!, chatId: breckId,
                             sender: rowan, body: "joined", createdAt: readTo.addingTimeInterval(30 * 60),
                             kind: "joined")
        let hello = Message(id: UUID(uuidString: "F0000000-0000-4000-8000-000000000002")!, chatId: breckId,
                            sender: rowan, body: "hey! Maya sent me the code. what did I miss? 👀",
                            createdAt: readTo.addingTimeInterval(31 * 60))
        let newcomer = Member(userId: rowan, joinedAt: joined.createdAt, lastReadAt: breck.createdAt,
                              profile: Profile(id: rowan, displayName: "Rowan"))
        var chat = breck
        chat.memberCount = members.count + 1
        chat.lastMessageAt = hello.createdAt
        chat.lastMessagePreview = hello.body
        chat.lastMessageSenderName = "Rowan"
        chat.lastReadAt = readTo
        chat.unreadCount = 1
        return ChatModel.preview(chat: chat, myId: me, members: members + [newcomer],
                                 messages: messages + [joined, hello],
                                 catchUp: .done(brief), answer: .done(answer), delay: .seconds(1.5))
    }
}
#endif
