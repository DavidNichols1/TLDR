//
//  InviteView.swift
//  Ketchup
//
//  Invite friends: a chat's invite code in a message, sent two ways. Text a
//  friend opens Apple's contact picker (no Contacts permission, nothing
//  uploaded: Cetchup only gets the one number you pick, to hand to
//  Messages) and then a Messages draft. Share another way is the system
//  share sheet. From Settings and Your people.
//
//  Finding friends by matching your contacts against Ketchup accounts is
//  left out on purpose: it would mean uploading your friends' numbers.
//

import SwiftUI
import ContactsUI
import MessageUI

struct InviteView: View {
    @Environment(AppModel.self) private var app
    @State private var chatId: UUID?

    private var chat: ChatSummary? { app.chats.first { $0.id == chatId } ?? app.chats.first }
    private var message: String { InviteMessage.text(for: chat) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Kicker("Invite friends")
                    Text("Bring your people in")
                        .font(.serif(.largeTitle))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text("Send a chat's invite code. When they join, the whole chat is there, ready to catch up on.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }

                if app.chats.count > 1 {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle("Which chat?")
                        VStack(spacing: 0) {
                            ForEach(app.chats) { option in
                                chatRow(option)
                                if option.id != app.chats.last?.id { SettingsHairline() }
                            }
                        }
                        .paperCard(padding: 0)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Kicker("What they'll get")
                    Text(message)
                        .font(.body)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                .paperCard(padding: 16)

                VStack(spacing: 10) {
                    Button {
                        InviteTexter.shared.start(message: message)
                    } label: {
                        Label("Text a friend", systemImage: "message")
                    }
                    .buttonStyle(.ketchup)

                    ShareLink(item: message) {
                        Label("Share another way", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.outline)
                }

                Text("You pick one person in Apple's contact list. Cetchup only gets that number, to open Messages, and doesn't keep it or send it anywhere.")
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(Theme.cream)
        .navigationTitle("Invite friends")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Color.clear.frame(width: 1, height: 1).accessibilityHidden(true)
            }
        }
    }

    private func chatRow(_ option: ChatSummary) -> some View {
        let on = option.id == chat?.id
        return Button {
            chatId = option.id
        } label: {
            HStack(spacing: 12) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.body.weight(.medium))
                    .foregroundStyle(on ? Theme.ink : Theme.inkFaint)
                    .frame(width: 24)
                    .contentTransition(.symbolEffect(.replace))
                Text(option.name)
                    .font(.body)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(option.inviteCode)
                    .font(.mono(.footnote))
                    .foregroundStyle(Theme.inkSoft)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(.rect)
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// The invite's words.
enum InviteMessage {
    /// Where to get Ketchup, once it has a public link (TestFlight or the
    /// App Store). Until then the message carries the name and the code.
    static let appLink: URL? = nil

    /// "I'm on Cetchup… Join “Breck Weekend 🎿” with code WQGAEA." Join with
    /// code pulls the code back out of a pasted message (JoinChatSheet.clean).
    static func text(for chat: ChatSummary?) -> String {
        var parts = ["I'm on Cetchup, a group chat that catches you up on what you missed."]
        if let chat { parts.append("Join “\(chat.name)” with code \(chat.inviteCode).") }
        if let appLink { parts.append(appLink.absoluteString) }
        return parts.joined(separator: " ")
    }
}

/// Text a friend: Apple's contact picker, then a Messages draft to the number
/// picked. A phone that can't text (or the simulator) gets the share sheet.
@MainActor
final class InviteTexter: NSObject {
    static let shared = InviteTexter()

    private var message = ""

    func start(message: String) {
        guard let top = Self.topViewController() else { return }
        self.message = message
        let picker = CNContactPickerViewController()
        picker.delegate = self
        picker.displayedPropertyKeys = [CNContactPhoneNumbersKey]
        picker.predicateForEnablingContact = NSPredicate(format: "phoneNumbers.@count > 0")
        // One number: picking the person picks it. Several: they pick which.
        picker.predicateForSelectionOfContact = NSPredicate(format: "phoneNumbers.@count == 1")
        top.present(picker, animated: true)
    }

    private func compose(to number: String) {
        Task {
            // The picker closes itself first.
            try? await Task.sleep(for: .milliseconds(450))
            guard let top = Self.topViewController() else { return }
            guard MFMessageComposeViewController.canSendText() else {
                top.present(UIActivityViewController(activityItems: [message], applicationActivities: nil), animated: true)
                return
            }
            let draft = MFMessageComposeViewController()
            draft.messageComposeDelegate = self
            draft.recipients = [number]
            draft.body = message
            top.present(draft, animated: true)
        }
    }

    /// The controller on top of everything (a sheet, if one is up).
    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        guard var top = scene?.keyWindow?.rootViewController else { return nil }
        while let next = top.presentedViewController, !next.isBeingDismissed {
            top = next
        }
        return top
    }
}

extension InviteTexter: CNContactPickerDelegate {
    /// A contact with one number.
    func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
        guard let number = contact.phoneNumbers.first?.value.stringValue else { return }
        compose(to: number)
    }

    /// One of a contact's numbers.
    func contactPicker(_ picker: CNContactPickerViewController, didSelect contactProperty: CNContactProperty) {
        guard let number = (contactProperty.value as? CNPhoneNumber)?.stringValue else { return }
        compose(to: number)
    }
}

extension InviteTexter: MFMessageComposeViewControllerDelegate {
    func messageComposeViewController(_ controller: MFMessageComposeViewController,
                                      didFinishWith result: MessageComposeResult) {
        controller.dismiss(animated: true)
    }
}

/// Invite friends from the inbox's "+" menu, in a sheet of its own with Done.
struct InviteSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            InviteView()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .presentationBackground(Theme.cream)
    }
}
