//
//  FormPieces.swift
//  Ketchup
//
//  What the chat screens type into: a text field drawn as paper, and code
//  boxes (the emailed sign-in code, a chat's invite code) that are really
//  one hidden field, so typing, pasting, autofill and VoiceOver all see a
//  single text field.
//

import SwiftUI

extension View {
    /// A text field on paper: card fill and a hairline that turns ink while
    /// the field has focus.
    func paperField(focused: Bool = false) -> some View {
        modifier(PaperField(focused: focused))
    }
}

private struct PaperField: ViewModifier {
    let focused: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        content
            .font(.body)
            .foregroundStyle(Theme.ink)
            .tint(Theme.ketchupText)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Theme.card, in: shape)
            .overlay {
                shape.strokeBorder(focused ? Theme.ink : Theme.rule, lineWidth: focused ? 1.5 : 1)
            }
            .motion(value: focused)
    }
}

/// A code typed one character per box. The boxes only draw `text`; an
/// invisible field on top of them does the typing, so the system's code
/// autofill, paste and VoiceOver all treat it as one field. The parent
/// filters and caps `text` (and submits when it's full).
struct CodeField: View {
    enum Kind {
        /// The emailed sign-in code: number pad, autofill from Mail.
        case digits
        /// A chat's invite code: capital letters and numbers.
        case inviteCode
    }

    @Binding var text: String
    let length: Int
    let kind: Kind
    var focus: FocusState<Bool>.Binding
    /// What VoiceOver calls the field, e.g. "Sign-in code".
    let label: String
    var onSubmit: () -> Void = {}

    var body: some View {
        CodeBoxes(text: text, length: length, active: focus.wrappedValue)
            .contentShape(.rect)
            .onTapGesture { focus.wrappedValue = true }
            .accessibilityHidden(true)
            .overlay { field }
    }

    @ViewBuilder
    private var field: some View {
        let input = TextField("", text: $text)
            .font(.mono(.title2))
            .foregroundStyle(.clear)
            .tint(.clear)
            .autocorrectionDisabled()
            .focused(focus)
            .onSubmit(onSubmit)
            .accessibilityLabel(label)
            .accessibilityHint(kind == .digits ? "\(length) digits" : "\(length) letters and numbers")
        switch kind {
        case .digits:
            input
                .textContentType(.oneTimeCode)
                .keyboardType(.numberPad)
        case .inviteCode:
            input
                .textInputAutocapitalization(.characters)
                .keyboardType(.asciiCapable)
                .submitLabel(.join)
        }
    }
}

/// The boxes themselves: one SF Mono character each, a ketchup caret in the
/// next empty box while the field has focus, and a wider gap halfway so a
/// long code reads in two halves (1234 5678, WQG AEA).
private struct CodeBoxes: View {
    let text: String
    let length: Int
    let active: Bool

    var body: some View {
        let half = length >= 6 ? length / 2 : length
        HStack(spacing: 14) {
            boxes(0..<half)
            if half < length { boxes(half..<length) }
        }
    }

    private func boxes(_ range: Range<Int>) -> some View {
        let characters = Array(text.prefix(length))
        return HStack(spacing: 6) {
            ForEach(range, id: \.self) { index in
                box(index < characters.count ? String(characters[index]) : nil,
                    isNext: active && index == characters.count)
            }
        }
    }

    private func box(_ character: String?, isNext: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return Text(character ?? "0")
            .font(.mono(.title2, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .opacity(character == nil ? 0 : 1)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .overlay {
                if isNext { BlinkingCaret() }
            }
            .background(Theme.card, in: shape)
            .overlay {
                shape.strokeBorder(isNext ? Theme.ink : Theme.rule, lineWidth: isNext ? 1.5 : 1)
            }
            .motion(value: isNext)
    }
}

/// The caret in the next empty box. It holds still with Reduce Motion on.
private struct BlinkingCaret: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    var body: some View {
        Capsule()
            .fill(Theme.ketchupText)
            .frame(width: 2)
            .padding(.vertical, 14)
            .opacity(dim ? 0.15 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.55).repeatForever()) { dim = true }
            }
    }
}

/// Footnote-sized trouble ("That code didn't work") in small ketchup red.
struct FormError: View {
    let text: String

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "exclamationmark.circle")
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(Theme.ketchupText)
        .fixedSize(horizontal: false, vertical: true)
    }
}
