//
//  CatchUpSheet.swift
//  TLDR
//
//  "Catch me up": Muse Spark reads everything since your read cursor and
//  this sheet lays out what came back. Reopening it shows the same brief
//  unless new messages have arrived since.
//

import SwiftUI

struct CatchUpSheet: View {
    let model: ChatModel
    let refs: RefContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    content
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
            .background(alignment: .top) {
                Theme.aiDiagonal.opacity(0.10)
                    .frame(height: 260)
                    .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
                    .ignoresSafeArea()
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDragIndicator(.visible)
        // Unstructured on purpose: swiping the sheet away mid-request
        // shouldn't cancel it; the brief is waiting when it reopens.
        .onAppear { Task { await model.catchUpIfNeeded() } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            AILabel()
            Text("Catch me up")
                .font(.largeTitle.bold())
            Text(model.chat.name)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.catchUp {
        case .idle, .loading:
            SparkleLoading(title: model.unreadAtOpen > 0
                           ? "Reading \(model.unreadAtOpen) messages…"
                           : "Reading the chat…")
        case .failed(let message):
            AIErrorCard(message: message) {
                Task { await model.runCatchUp() }
            }
        case .done(let response):
            if let brief = response.result {
                CatchUpContent(brief: brief, chatName: model.chat.name, refs: refs)
                meta(response)
            } else {
                allCaughtUp
            }
        }
    }

    private var allCaughtUp: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.aiGradient)
            Text("You're all caught up")
                .font(.title3.bold())
            Text("Nothing new since you last read this chat. Try Ask the chat to look something up.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .aiCard(padding: 24)
    }

    /// Small print: how many messages, how long, which model, cached or not.
    private func meta(_ r: BriefResponse<CatchUp>) -> some View {
        var parts: [String] = []
        if let n = r.messageCount { parts.append(n == 1 ? "1 message" : "\(n) messages") }
        if r.cached == true { parts.append("cached") }
        else if let ms = r.latencyMs { parts.append(String(format: "%.1f s", Double(ms) / 1000)) }
        if let m = r.model, !m.isEmpty { parts.append(m) }
        return Text(parts.joined(separator: " · "))
            .font(.caption2.monospaced())
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
    }
}

/// A failed Muse Spark call: what happened, and a retry.
struct AIErrorCard: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.bubble")
                .font(.system(size: 36))
                .foregroundStyle(Theme.aiGradient)
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
            Button("Try again", action: retry)
                .buttonStyle(.aiPillCompact)
        }
        .frame(maxWidth: .infinity)
        .aiCard(padding: 22)
    }
}
