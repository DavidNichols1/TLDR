//
//  SignInView.swift
//  TLDR
//
//  Email → 6-digit code → in. The account is created on the first code.
//

import SwiftUI

struct SignInView: View {
    private enum Step { case email, code }

    @State private var step = Step.email
    @State private var email = ""
    @State private var code = ""
    @State private var busy = false
    @State private var error: String?
    @FocusState private var focused: Bool

    private var validEmail: Bool {
        let e = email.trimmingCharacters(in: .whitespaces)
        return e.contains("@") && e.contains(".") && e.count >= 5
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                hero
                    .padding(.top, 60)

                VStack(spacing: 14) {
                    switch step {
                    case .email: emailStep
                    case .code:  codeStep
                    }
                    if let error {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 24)
            }
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(alignment: .top) {
            Theme.aiDiagonal.opacity(0.14)
                .frame(height: 420)
                .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
                .ignoresSafeArea()
        }
    }

    private var hero: some View {
        VStack(spacing: 12) {
            Text("TL;DR")
                .font(.system(size: 56, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.aiDiagonal)
            Text("Come back to 300 unread messages\nand know what matters in seconds.")
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            AILabel(text: "Powered by Muse Spark")
                .padding(.top, 4)
        }
    }

    private var emailStep: some View {
        VStack(spacing: 14) {
            TextField("you@example.com", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused)
                .submitLabel(.continue)
                .onSubmit { Task { await sendCode() } }
                .fieldStyle()

            Button {
                Task { await sendCode() }
            } label: {
                primaryLabel("Email me a code")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!validEmail || busy)

            Text("We'll send a 6-digit code. New here? That makes your account.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var codeStep: some View {
        VStack(spacing: 14) {
            Text("Enter the code we sent to\n**\(email)**")
                .multilineTextAlignment(.center)

            TextField("123456", text: $code)
                .textContentType(.oneTimeCode)
                .keyboardType(.numberPad)
                .font(.system(.title, design: .monospaced).weight(.semibold))
                .multilineTextAlignment(.center)
                .focused($focused)
                .fieldStyle()
                .onChange(of: code) { _, new in
                    let digits = String(new.filter(\.isNumber).prefix(6))
                    if digits != new { code = digits }
                    if digits.count == 6 { Task { await verify() } }
                }

            Button {
                Task { await verify() }
            } label: {
                primaryLabel("Sign in")
            }
            .buttonStyle(.borderedProminent)
            .disabled(code.count != 6 || busy)

            HStack(spacing: 20) {
                Button("Different email") {
                    step = .email
                    code = ""
                    error = nil
                }
                Button("Resend code") {
                    Task { await sendCode() }
                }
                .disabled(busy)
            }
            .font(.footnote)
        }
    }

    private func primaryLabel(_ title: String) -> some View {
        ZStack {
            Text(title).opacity(busy ? 0 : 1)
            if busy { ProgressView().tint(.white) }
        }
        .font(.headline)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    // MARK: Actions

    private func sendCode() async {
        guard validEmail, !busy else { return }
        busy = true
        error = nil
        defer { busy = false }
        email = email.trimmingCharacters(in: .whitespaces).lowercased()
        do {
            try await Supabase.shared.sendCode(to: email)
            step = .code
            code = ""
            focused = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func verify() async {
        guard code.count == 6, !busy else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            // Success flips AppModel.session; RootView moves on by itself.
            try await Supabase.shared.verifyCode(email: email, code: code)
        } catch {
            self.error = error.localizedDescription
            code = ""
        }
    }
}

private extension View {
    func fieldStyle() -> some View {
        padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
