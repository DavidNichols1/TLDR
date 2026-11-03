//
//  AskSheet.swift
//  TLDR
//
//  "Ask the chat": a question in, an answer out with the messages that
//  back it up. Muse Spark says so plainly when the chat doesn't have it.
//

import SwiftUI

struct AskSheet: View {
    let model: ChatModel
    let refs: RefContext
    @Environment(\.dismiss) private var dismiss
    @State private var question = ""
    @FocusState private var focused: Bool

    private static let suggestions = [
        "What did we decide?",
        "When and where are we meeting?",
        "Who's bringing what?",
        "Does anyone owe me money?",
        "Did anyone answer my question?",
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        AILabel()
                        Text("Ask the chat")
                            .font(.largeTitle.bold())
                    }

                    field

                    if model.answer.value == nil && !model.answer.isLoading {
                        suggestionChips
                    }

                    result
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDragIndicator(.visible)
        .onAppear {
            if question.isEmpty { question = model.lastQuestion }
            if model.answer.value == nil { focused = true }
        }
    }

    private var field: some View {
        HStack(spacing: 8) {
            TextField("Ask anything about this chat", text: $question, axis: .vertical)
                .lineLimit(1...4)
                .focused($focused)
                .submitLabel(.send)
                .onSubmit(submit)
            Button(action: submit) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(canAsk ? AnyShapeStyle(Theme.aiGradient) : AnyShapeStyle(Color.secondary.opacity(0.4)))
            }
            .buttonStyle(.plain)
            .disabled(!canAsk)
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(Theme.aiGradient.opacity(focused ? 0.8 : 0.35), lineWidth: 1))
    }

    private var suggestionChips: some View {
        FlowLayout(spacing: 8) {
            ForEach(Self.suggestions, id: \.self) { s in
                Button {
                    question = s
                    submit()
                } label: {
                    Text(s)
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Theme.violet.opacity(0.10), in: Capsule())
                        .foregroundStyle(Theme.indigo)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var result: some View {
        switch model.answer {
        case .idle:
            EmptyView()
        case .loading:
            SparkleLoading(title: "Searching the chat…", lines: [1, 0.85, 0.6])
        case .failed(let message):
            AIErrorCard(message: message) { submit() }
        case .done(let response):
            if let answer = response.result {
                answerCard(answer)
            } else {
                AIErrorCard(message: "Muse Spark didn't answer that. Try asking another way.") { submit() }
            }
        }
    }

    private func answerCard(_ answer: ChatAnswer) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("“\(model.lastQuestion)”")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !answer.found {
                Label("Not in the chat", systemImage: "magnifyingglass")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.orange)
            }
            Text(answer.answer)
                .font(.body)
                .foregroundStyle(answer.found ? .primary : .secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !answer.refs.isEmpty {
                Text("From the chat")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                RefChips(refs: answer.refs, context: refs)
            }
        }
        .aiCard(padding: 18)
    }

    private var canAsk: Bool {
        !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !model.answer.isLoading
    }

    private func submit() {
        guard canAsk else { return }
        focused = false
        let q = question
        Task { await model.ask(q) }
    }
}
