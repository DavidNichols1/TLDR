//
//  ReportView.swift
//  Ketchup
//
//  Report a message (long press in the thread) or a person (from their
//  profile): what's wrong, an optional note, and "Block them too". The
//  server copies the message into the report and nobody can read it back
//  through the app; the person isn't told. After it's sent, a thank-you.
//

import SwiftUI

struct ReportView: View {
    let target: ReportTarget
    /// The root of a sheet (ReportSheet): Cancel until it's sent.
    var closesSheet = false
    /// Runs if "Block them too" blocked them, so an open chat can drop
    /// their messages at once.
    var onBlocked: () -> Void = {}

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reason: ReportReason?
    @State private var note = ""
    @State private var alsoBlock = false
    @State private var sending = false
    @State private var sent = false
    @State private var blockedToo = false
    @State private var error: String?
    @FocusState private var noteFocused: Bool

    private var person: Person { target.person }
    private var alreadyBlocked: Bool { PeopleStore.shared.isBlocked(person.id) }

    #if DEBUG
    /// Offline previews: open on the thank-you.
    init(target: ReportTarget, sent: Bool, closesSheet: Bool = false, onBlocked: @escaping () -> Void = {}) {
        self.target = target
        self.closesSheet = closesSheet
        self.onBlocked = onBlocked
        _sent = State(initialValue: sent)
        _reason = State(initialValue: sent ? .harassment : nil)
    }
    #endif

    init(target: ReportTarget, closesSheet: Bool = false, onBlocked: @escaping () -> Void = {}) {
        self.target = target
        self.closesSheet = closesSheet
        self.onBlocked = onBlocked
    }

    var body: some View {
        ScrollView {
            Group {
                if sent { thanks } else { form }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.cream)
        .navigationTitle("Report")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Report")
                    .font(.serif(.headline))
                    .foregroundStyle(Theme.ink)
            }
            if closesSheet && !sent {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .motion(Motion.settle, value: sent)
        .interactiveDismissDisabled(sending)
    }

    // MARK: The form

    private var form: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.serif(.title))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text("\(person.name) won't know it was you.")
                    .font(.body)
                    .foregroundStyle(Theme.inkSoft)
            }

            if case .message(let message, _) = target {
                quote(message)
            }

            VStack(alignment: .leading, spacing: 10) {
                SectionTitle("What's wrong?")
                VStack(spacing: 0) {
                    ForEach(ReportReason.allCases) { option in
                        reasonRow(option)
                        if option != ReportReason.allCases.last {
                            SettingsHairline()
                        }
                    }
                }
                .paperCard(padding: 0)
            }

            VStack(alignment: .leading, spacing: 10) {
                TextField("Anything we should know?", text: $note,
                          prompt: Text("Anything we should know? (optional)").foregroundStyle(Theme.inkFaint),
                          axis: .vertical)
                    .lineLimit(2...5)
                    .focused($noteFocused)
                    .paperField(focused: noteFocused)
                if !alreadyBlocked {
                    Toggle(isOn: $alsoBlock) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Block \(person.name) too")
                                .font(.body)
                                .foregroundStyle(Theme.ink)
                            Text("You won't see their messages in any chat.")
                                .font(.footnote)
                                .foregroundStyle(Theme.inkSoft)
                        }
                    }
                    .tint(Theme.ketchupText)
                    .paperCard(padding: 14)
                }
            }

            if let error {
                FormError(text: error)
            }

            Button {
                Task { await send() }
            } label: {
                ZStack {
                    Text("Send report").opacity(sending ? 0 : 1)
                    if sending { ProgressView().tint(Theme.onKetchup) }
                }
            }
            .buttonStyle(.ketchup)
            .disabled(reason == nil || sending)
        }
    }

    private var title: String {
        switch target {
        case .message: "Report this message"
        case .person(let person): "Report \(person.name)"
        }
    }

    /// The message being reported, on paper, under its sender's name.
    private func quote(_ message: Message) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Kicker(person.name, color: Theme.personColor(name: person.name))
            Text(message.previewText)
                .font(.body)
                .foregroundStyle(Theme.ink)
                .lineLimit(6)
                .fixedSize(horizontal: false, vertical: true)
            Text(message.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.mono(.caption2))
                .foregroundStyle(Theme.inkSoft)
        }
        .paperCard(padding: 16)
        .accessibilityElement(children: .combine)
    }

    private func reasonRow(_ option: ReportReason) -> some View {
        Button {
            reason = option
        } label: {
            HStack(spacing: 12) {
                Image(systemName: reason == option ? "checkmark.circle.fill" : "circle")
                    .font(.body.weight(.medium))
                    .foregroundStyle(reason == option ? Theme.ink : Theme.inkFaint)
                    .frame(width: 24)
                    .contentTransition(.symbolEffect(.replace))
                Text(option.label)
                    .font(.body)
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(.rect)
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(reason == option ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: reason) { _, now in now == option }
    }

    // MARK: Sent

    private var thanks: some View {
        VStack(spacing: 14) {
            KetchupDrop()
                .fill(Theme.ketchup)
                .frame(width: 56, height: 56)
                .rotationEffect(.degrees(-8))
                .accessibilityHidden(true)
                .padding(.bottom, 4)
            Text("Thanks for telling us")
                .font(.serif(.title2))
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            Text("We look at every report. \(person.name) won't know it was you.")
                .font(.body)
                .foregroundStyle(Theme.inkSoft)
            if blockedToo {
                Text("You've blocked \(person.name) too, so their messages are gone from your chats.")
                    .font(.body)
                    .foregroundStyle(Theme.inkSoft)
            }
            Button("Done") { dismiss() }
                .buttonStyle(.outline)
                .padding(.top, 8)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
        .transition(.rise(reduceMotion: reduceMotion))
    }

    // MARK: Sending

    private func send() async {
        guard let reason, !sending else { return }
        sending = true
        error = nil
        defer { sending = false }
        let id = UUID()
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if Previewing.isOn {
                try await Task.sleep(for: .milliseconds(400))
            } else {
                try await KetchupAPI.report(id: id, target, reason: reason, note: trimmed.isEmpty ? nil : trimmed)
                Task { await KetchupAPI.alertReport(id) }
            }
            if alsoBlock, !alreadyBlocked {
                try await PeopleStore.shared.block(person)
                blockedToo = true
                onBlocked()
                await app.refreshChats()
            }
            noteFocused = false
            sent = true
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// A report from the thread, in a sheet of its own.
struct ReportSheet: View {
    let target: ReportTarget
    var onBlocked: () -> Void = {}

    var body: some View {
        NavigationStack {
            ReportView(target: target, closesSheet: true, onBlocked: onBlocked)
        }
        .presentationBackground(Theme.cream)
    }
}
