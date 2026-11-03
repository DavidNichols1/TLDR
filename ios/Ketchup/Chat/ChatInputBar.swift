//
//  ChatInputBar.swift
//  Ketchup
//
//  Ported from AurariaGO's ChatComponents.ChatInputBar; the cap matches
//  messages_body_check (2,000 characters). A paper field and a ketchup
//  send button that only turns red when there's something to send. With
//  `onPhoto`, a photo button sits before the field, and a picked photo
//  waits above it until it's sent or taken off.
//

import SwiftUI

struct ChatInputBar: View {
    let placeholder: String
    @Binding var text: String
    var disabled = false
    /// A picked photo waiting to go with the next send.
    var attachment: UIImage? = nil
    /// Shows the photo button; called when it's tapped.
    var onPhoto: (() -> Void)? = nil
    var onRemoveAttachment: () -> Void = {}
    let onSend: () -> Void

    @FocusState private var focused: Bool
    @ScaledMetric(relativeTo: .body) private var sendSize: CGFloat = 40
    @ScaledMetric(relativeTo: .body) private var attachmentHeight: CGFloat = 76

    private var canSend: Bool {
        let ready = attachment == nil ? Self.sendable(text) != nil : Self.caption(text) != nil
        return ready && !disabled
    }

    var body: some View {
        let field = RoundedRectangle(cornerRadius: 20, style: .continuous)
        VStack(alignment: .leading, spacing: 8) {
            if let attachment {
                attachmentChip(attachment)
                    .padding(.leading, onPhoto == nil ? 0 : sendSize + 10)
            }
            HStack(alignment: .bottom, spacing: 10) {
                if let onPhoto {
                    Button(action: onPhoto) {
                        Image(systemName: "photo")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(disabled ? Theme.inkFaint : Theme.ink)
                            .frame(width: sendSize, height: sendSize)
                    }
                    .buttonStyle(.pressable)
                    .disabled(disabled)
                    .accessibilityLabel(attachment == nil ? "Add a photo" : "Pick a different photo")
                }

                TextField(placeholder, text: $text, prompt: Text(placeholder).foregroundStyle(Theme.inkFaint), axis: .vertical)
                    .lineLimit(1...5)
                    .font(.body)
                    .foregroundStyle(Theme.ink)
                    .tint(Theme.ketchupText)
                    .focused($focused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .frame(minHeight: sendSize)
                    .background(Theme.card, in: field)
                    .overlay {
                        field.strokeBorder(focused ? Theme.inkSoft : Theme.rule, lineWidth: 1)
                    }
                    .disabled(disabled)

                Button(action: onSend) {
                    Image(systemName: "arrow.up")
                        .font(.body.weight(.bold))
                        .foregroundStyle(canSend ? Theme.onKetchup : Theme.inkFaint)
                        .frame(width: sendSize, height: sendSize)
                        .background(canSend ? Theme.ketchup : Theme.rule, in: Circle())
                }
                .buttonStyle(.pressable)
                .disabled(!canSend)
                .accessibilityLabel(attachment == nil ? "Send" : "Send photo")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.cream)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.rule).frame(height: 1)
        }
        .motion(value: canSend)
        .motion(value: focused)
        .motion(value: attachment != nil)
    }

    /// The photo waiting to go, with a way to take it off.
    private func attachmentChip(_ image: UIImage) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        let ratio = min(max(image.size.width / max(image.size.height, 1), 0.6), 1.8)
        return Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: attachmentHeight * ratio, height: attachmentHeight)
            .clipShape(shape)
            .overlay { shape.strokeBorder(Theme.rule, lineWidth: 1) }
            .overlay(alignment: .topTrailing) {
                Button(action: onRemoveAttachment) {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.onInk)
                        .frame(width: 22, height: 22)
                        .background(Theme.ink, in: Circle())
                        .padding(5)
                        .contentShape(.rect)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Remove photo")
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Photo to send")
    }

    /// The trimmed text, or nil when it's empty or over the cap.
    static func sendable(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return (t.isEmpty || t.count > 2000) ? nil : t
    }

    /// A photo's caption: the trimmed text, which may be empty; nil over the cap.
    static func caption(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count > 2000 ? nil : t
    }
}
