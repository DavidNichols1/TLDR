//
//  InstagramAPI.swift
//  Ketchup
//
//  EXPERIMENTAL, NOT RELEASED. Sends a thread read off Instagram to the
//  catch-up-text edge function (the same Muse Spark pipeline as Ketchup's
//  own chats). The server stores nothing from it; this side doesn't either.
//

import Foundation

enum InstagramAPI {

    static func catchUp(_ thread: IGThread, readerName: String) async throws -> BriefResponse<CatchUp> {
        try await call(body(thread, readerName: readerName, mode: "catch_up"))
    }

    static func ask(_ question: String, about thread: IGThread, readerName: String) async throws -> BriefResponse<ChatAnswer> {
        var request = body(thread, readerName: readerName, mode: "ask")
        request["question"] = question
        return try await call(request)
    }

    /// My messages go under the reader's Ketchup name, so "For you" and
    /// questions aimed at them by name come out right.
    private static func body(_ thread: IGThread, readerName: String, mode: String) -> [String: Any] {
        [
            "mode": mode,
            "source": "instagram",
            "thread_title": thread.title,
            "reader_name": readerName,
            "time_zone": TimeZone.current.identifier,
            "messages": thread.messages.map { m -> [String: Any] in
                var row: [String: Any] = ["sender": m.isMe ? readerName : m.sender, "text": m.text]
                if let at = m.at { row["at"] = at }
                return row
            },
        ]
    }

    private static func call<Result: Decodable>(_ body: [String: Any]) async throws -> BriefResponse<Result> {
        let data = try await Supabase.shared.function("catch-up-text", body)
        let rewritten = IGRef.rewrite(try JSONSerialization.jsonObject(with: data))
        return try JSON.decoder.decode(BriefResponse<Result>.self, from: JSONSerialization.data(withJSONObject: rewritten))
    }
}
