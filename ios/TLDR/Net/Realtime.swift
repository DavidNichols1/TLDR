//
//  Realtime.swift
//  TLDR
//
//  Supabase Realtime over URLSessionWebSocketTask (Phoenix protocol 1.0.0,
//  JSON frames) — new in TLDR; AurariaGO polls. One socket per open chat:
//  join "realtime:chat-<id>" with a postgres_changes filter on that chat's
//  messages, heartbeat every 25 s, and pass the member's access token so
//  Realtime applies the messages select policy (non-members get nothing).
//
//  If the socket drops, it reconnects with backoff; ChatView polls while
//  `isLive` is false, so messages still arrive.
//

import Foundation
import Observation

@Observable
final class ChatRealtime {

    private(set) var isLive = false

    private let chatId: UUID
    private let onInsert: (Message) -> Void

    private var socket: URLSessionWebSocketTask?
    private var heartbeat: Task<Void, Never>?
    private var receiver: Task<Void, Never>?
    private var ref = 0
    private var joinRef = ""
    private var sentToken: String?
    private var stopped = true
    private var failures = 0

    private var topic: String { "realtime:chat-\(chatId.uuidString.lowercased())" }

    init(chatId: UUID, onInsert: @escaping (Message) -> Void) {
        self.chatId = chatId
        self.onInsert = onInsert
    }

    func start() {
        guard stopped else { return }
        stopped = false
        Task { await connect() }
    }

    func stop() {
        stopped = true
        isLive = false
        heartbeat?.cancel()
        receiver?.cancel()
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
    }

    // MARK: - Connection

    private func connect() async {
        guard !stopped, let token = await Supabase.shared.freshAccessToken() else { return }
        let task = URLSession.shared.webSocketTask(with: Config.realtimeURL)
        socket = task
        task.resume()

        ref += 1
        joinRef = String(ref)
        sentToken = token
        let filter = "chat_id=eq.\(chatId.uuidString.lowercased())"
        send([
            "topic": topic,
            "event": "phx_join",
            "ref": joinRef,
            "join_ref": joinRef,
            "payload": [
                "config": [
                    "broadcast": ["ack": false, "self": false],
                    "presence": ["enabled": false],
                    "postgres_changes": [
                        ["event": "INSERT", "schema": "public", "table": "messages", "filter": filter],
                    ],
                    "private": false,
                ],
                "access_token": token,
            ],
        ])

        receiver?.cancel()
        receiver = Task { [weak self] in await self?.receiveLoop(task) }
        heartbeat?.cancel()
        heartbeat = Task { [weak self] in await self?.heartbeatLoop() }
    }

    private func receiveLoop(_ task: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            let frame: URLSessionWebSocketTask.Message
            do {
                frame = try await task.receive()
            } catch {
                await dropped()
                return
            }
            let data: Data?
            switch frame {
            case .string(let s): data = s.data(using: .utf8)
            case .data(let d):   data = d
            @unknown default:    data = nil
            }
            if let data { handle(data) }
        }
    }

    private func heartbeatLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(25))
            if Task.isCancelled { return }
            ref += 1
            send(["topic": "phoenix", "event": "heartbeat", "payload": [:], "ref": String(ref)])
            // Tokens last an hour; hand Realtime the new one when it changes.
            if let token = await Supabase.shared.freshAccessToken(), token != sentToken {
                sentToken = token
                ref += 1
                send(["topic": topic, "event": "access_token", "payload": ["access_token": token],
                      "ref": String(ref), "join_ref": joinRef])
            }
        }
    }

    private func dropped() async {
        isLive = false
        heartbeat?.cancel()
        socket = nil
        guard !stopped else { return }
        failures += 1
        let wait = min(30.0, pow(2.0, Double(min(failures, 5))))
        try? await Task.sleep(for: .seconds(wait))
        if !stopped { await connect() }
    }

    // MARK: - Frames

    private func handle(_ data: Data) {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = obj["event"] as? String,
              (obj["topic"] as? String) == topic else { return }
        let payload = obj["payload"] as? [String: Any] ?? [:]

        switch event {
        case "phx_reply":
            guard (obj["ref"] as? String) == joinRef else { return }
            if (payload["status"] as? String) == "ok" {
                isLive = true
                failures = 0
            } else {
                print("[realtime] join refused: \(payload)")
                isLive = false
            }
        case "system":
            // e.g. postgres_changes subscription status; an error means no events.
            if (payload["status"] as? String) == "error" {
                print("[realtime] system error: \(payload)")
                isLive = false
            }
        case "postgres_changes":
            guard let change = payload["data"] as? [String: Any],
                  (change["type"] as? String) == "INSERT",
                  let record = change["record"],
                  let recordData = try? JSONSerialization.data(withJSONObject: record),
                  let message = try? JSON.decoder.decode(Message.self, from: recordData) else { return }
            onInsert(message)
        case "phx_error", "phx_close":
            isLive = false
            socket?.cancel(with: .goingAway, reason: nil)
        default:
            break
        }
    }

    private func send(_ object: [String: Any]) {
        guard let socket,
              let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else { return }
        socket.send(.string(text)) { error in
            if let error { print("[realtime] send failed: \(error.localizedDescription)") }
        }
    }
}
