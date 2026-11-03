//
//  DedupeTestRow.swift
//  Ketchup
//
//  DEBUG builds, Settings › On this iPhone: asks the catch-up-speed-test
//  function the same question twice at once, in your first chat, to see the
//  server answer both from one Muse Spark call (supabase/functions/_shared/
//  once.ts). Only while that test function is deployed. The alert shows each
//  answer's brief id, whether it came back saved, and how long it took; the
//  function's log shows how many Muse Spark calls there were.
//

#if DEBUG
import SwiftUI

struct DedupeTestRow: View {
    @Environment(AppModel.self) private var app
    @State private var running = false
    @State private var result: String?

    var body: some View {
        if !PreviewData.isActive {
            Button { Task { await run() } } label: {
                SettingsRow("Test: two identical asks at once", systemImage: "testtube.2",
                            detail: running ? "Asking twice…" : "catch-up-speed-test, in your first chat")
            }
            .buttonStyle(.pressable)
            .disabled(running || app.chats.isEmpty)
            .alert("Two identical asks", isPresented: Binding(get: { result != nil }, set: { if !$0 { result = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(result ?? "")
            }
        }
    }

    private func run() async {
        guard let chat = app.chats.first else { return }
        running = true
        defer { running = false }
        // A new question each run, so the answer isn't the last run's, saved.
        let question = "When are we leaving? (test \(Date.now.formatted(date: .omitted, time: .standard)))"
        let started = Date.now
        async let first = Self.ask(question, in: chat.id, since: started)
        async let second = Self.ask(question, in: chat.id, since: started)
        let lines = await [first, second]
        result = lines.joined(separator: "\n")
        print("[dedupe-test] \(lines.joined(separator: " | "))")
    }

    /// "brief 5a0e12ab, made here, 3.1 s" or "…, saved, 3.2 s".
    private static func ask(_ question: String, in chat: UUID, since started: Date) async -> String {
        do {
            let data = try await Supabase.shared.function("catch-up-speed-test", [
                "chat_id": chat.uuidString, "mode": "ask", "question": question,
                "time_zone": TimeZone.current.identifier,
            ])
            let response = try JSON.decoder.decode(BriefResponse<ChatAnswer>.self, from: data)
            let seconds = Date.now.timeIntervalSince(started).formatted(.number.precision(.fractionLength(1)))
            let id = response.briefId.map { String($0.uuidString.prefix(8)).lowercased() } ?? "none"
            return "brief \(id), \(response.cached == true ? "saved" : "made here"), \(seconds) s"
        } catch {
            return "failed: \(error.localizedDescription)"
        }
    }
}
#endif
