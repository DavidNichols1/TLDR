//
//  InstagramResultView.swift
//  Ketchup
//
//  EXPERIMENTAL, NOT RELEASED. The catch-up for an Instagram thread: the same
//  sections as a Ketchup chat's catch-up, but each source chip quotes the
//  message (there is no message in Ketchup to jump to). Minimal on purpose:
//  it gets the app's design once the redesign lands.
//

import SwiftUI

struct InstagramResultView: View {
    let result: IGCatchUpResult
    let readerName: String

    @Environment(\.dismiss) private var dismiss
    @State private var question = ""
    @State private var asking = false
    @State private var answer: ChatAnswer?
    @State private var askError: String?

    private var brief: CatchUp { result.brief }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    Text(brief.tldr)
                        .font(.title3.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    if !brief.forYou.isEmpty {
                        section("For you", "person.crop.circle.badge.exclamationmark") {
                            ForEach(Array(brief.forYou.enumerated()), id: \.offset) { _, item in
                                row(item.text, refs: item.refs)
                            }
                        }
                    }
                    if !brief.plans.isEmpty {
                        section("Plans", "calendar") {
                            ForEach(Array(brief.plans.enumerated()), id: \.offset) { _, plan in
                                planRow(plan)
                            }
                        }
                    }
                    if !brief.openQuestions.isEmpty {
                        section("Still unanswered", "questionmark.bubble") {
                            ForEach(Array(brief.openQuestions.enumerated()), id: \.offset) { _, q in
                                row(q.question, caption: q.askedBy.map { "Asked by \($0)" }, refs: q.refs)
                            }
                        }
                    }
                    if !brief.owes.isEmpty {
                        section("Who owes what", "arrow.left.arrow.right") {
                            ForEach(Array(brief.owes.enumerated()), id: \.offset) { _, o in
                                row(o.owesWhom.map { "\(o.who) → \($0): \(o.what)" } ?? "\(o.who): \(o.what)", refs: o.refs)
                            }
                        }
                    }
                    if !brief.highlights.isEmpty {
                        section("Highlights", "star") {
                            ForEach(Array(brief.highlights.enumerated()), id: \.offset) { _, item in
                                row(item.text, refs: item.refs)
                            }
                        }
                    }

                    ask
                    footer
                }
                .padding(20)
            }
            .navigationTitle(result.thread.displayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    // MARK: Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Muse Spark", systemImage: "sparkles")
                .font(.caption.weight(.bold))
                .foregroundStyle(.purple)
            Text("\(result.thread.messages.count) messages from Instagram · experimental")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func section<Content: View>(_ title: String, _ symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol).font(.headline)
            content()
        }
    }

    private func row(_ text: String, caption: String? = nil, refs: [UUID]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text).fixedSize(horizontal: false, vertical: true)
            if let caption { Text(caption).font(.caption).foregroundStyle(.secondary) }
            quotes(refs)
        }
    }

    private func planRow(_ plan: CatchUp.Plan) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(plan.title).font(.body.weight(.semibold))
                Spacer()
                Text(plan.confirmed ? "Confirmed" : "Proposed")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background((plan.confirmed ? Color.green : Color.orange).opacity(0.15), in: Capsule())
            }
            if let start = plan.start {
                Label(plan.allDay ? start.formatted(.dateTime.weekday(.wide).month().day())
                                  : start.formatted(.dateTime.weekday(.wide).month().day().hour().minute()),
                      systemImage: "clock")
                    .font(.subheadline)
            }
            if let location = plan.location { Label(location, systemImage: "mappin.and.ellipse").font(.subheadline) }
            if !plan.who.isEmpty { Label(plan.who.joined(separator: ", "), systemImage: "person.2").font(.subheadline) }
            quotes(plan.refs)
        }
        .padding(14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func quotes(_ refs: [UUID]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(refs, id: \.self) { ref in
                QuoteChip(message: IGRef.index(ref).flatMap { result.thread.messages.indices.contains($0) ? result.thread.messages[$0] : nil },
                          readerName: readerName)
            }
        }
    }

    // MARK: Ask

    private var ask: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Ask this chat", systemImage: "text.bubble").font(.headline)
            HStack {
                TextField("What time are we leaving?", text: $question)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.send)
                    .onSubmit { Task { await send() } }
                Button { Task { await send() } } label: {
                    if asking { ProgressView() } else { Text("Ask") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(asking || question.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let answer {
                VStack(alignment: .leading, spacing: 6) {
                    Text(answer.answer).fixedSize(horizontal: false, vertical: true)
                    if !answer.found { Text("Not in the messages Ketchup read.").font(.caption).foregroundStyle(.secondary) }
                    quotes(answer.refs)
                }
            }
            if let askError { Text(askError).font(.caption).foregroundStyle(.red) }
        }
    }

    private func send() async {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !asking else { return }
        asking = true
        askError = nil
        defer { asking = false }
        do {
            let reply = try await InstagramAPI.ask(String(q.prefix(500)), about: result.thread, readerName: readerName)
            guard let a = reply.result else { throw APIError.badResponse }
            answer = a
        } catch {
            askError = InstagramError.message(for: error)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(result.thread.reachedStart && !result.thread.truncated
                 ? "Covers the whole chat."
                 : "Covers the newest \(result.thread.messages.count) messages Instagram had loaded.")
            Text("Sent to Muse Spark to summarize. Nothing from this chat was saved.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

/// A source chip: who said it and what they said. Tap to see all of it.
private struct QuoteChip: View {
    let message: IGMessage?
    let readerName: String
    @State private var expanded = false

    var body: some View {
        if let message {
            Button { expanded.toggle() } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(message.isMe ? readerName : message.sender)
                        .font(.caption.weight(.semibold))
                    Text("“\(message.text)”")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(expanded ? nil : 1)
                        .multilineTextAlignment(.leading)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.purple.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityHint(expanded ? "Shows less" : "Shows the whole message")
        }
    }
}
