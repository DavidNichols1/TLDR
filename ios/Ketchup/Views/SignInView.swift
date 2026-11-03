//
//  SignInView.swift
//  Ketchup
//
//  Email → emailed code (Config.otpLength digits) → in. The account is created on the first code.
//

import SwiftUI

struct SignInView: View {
    private enum Step { case email, code }

    @State private var step = Step.email
    @State private var email = ""
    @State private var code = ""
    @State private var busy = false
    @State private var error: String?
    @State private var notice: String?
    /// Supabase allows one code email per address every 60 s; show it instead of failing silently.
    @State private var cooldown = 0
    @FocusState private var focused: Bool

    private var validEmail: Bool {
        let e = email.trimmingCharacters(in: .whitespaces)
        return e.contains("@") && e.contains(".") && e.count >= 5
    }

    /// "an 8-digit code", "a 6-digit code".
    private var codePhrase: String {
        let n = Config.otpLength
        let an = String(n).hasPrefix("8") || n == 11 || n == 18
        return "\(an ? "an" : "a") \(n)-digit code"
    }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Wordmark(size: 40, drawIn: true)
                        .padding(.top, 28)
                        .padding(.bottom, 36)

                    Group {
                        switch step {
                        case .email: emailStep
                        case .code: codeStep
                        }
                    }
                    .transition(.opacity)

                    messages
                        .padding(.top, 14)

                    Spacer(minLength: 40)
                    byline
                        .padding(.bottom, 12)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: 520, minHeight: geo.size.height, alignment: .topLeading)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Theme.cream)
        .motion(Motion.fade, value: step)
        #if DEBUG
        .task {
            // Offline preview of the code step: run the resend countdown.
            if PreviewData.isActive && step == .code && cooldown > 0 {
                focused = true
                startCooldown(cooldown)
            }
        }
        #endif
    }

    // MARK: Steps

    private var emailStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Missed 300 messages?")
                .font(.serif(.largeTitle))
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            Text("Ketchup reads the backlog and serves up the plans, who owes what, and what people asked you.")
                .font(.body)
                .foregroundStyle(Theme.inkSoft)
                .padding(.top, 10)

            TextField("Email", text: $email, prompt: Text(verbatim: "you@example.com").foregroundStyle(Theme.inkFaint))
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused)
                .submitLabel(.continue)
                .onSubmit { Task { await sendCode() } }
                .paperField(focused: focused)
                .padding(.top, 28)

            Button {
                Task { await sendCode() }
            } label: {
                busyLabel("Email me a code")
            }
            .buttonStyle(.ketchup)
            .disabled(!validEmail || busy)
            .padding(.top, 12)

            Text("We'll email you \(codePhrase). New here? That makes your account.")
                .font(.footnote)
                .foregroundStyle(Theme.inkSoft)
                .padding(.top, 12)
        }
    }

    private var codeStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Check your email")
                .font(.serif(.largeTitle))
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            Text("We sent \(codePhrase) to \(Text(email).fontWeight(.semibold).foregroundStyle(Theme.ink)).")
                .font(.body)
                .foregroundStyle(Theme.inkSoft)
                .padding(.top, 10)

            CodeField(text: $code, length: Config.otpLength, kind: .digits, focus: $focused, label: "Sign-in code")
                .padding(.top, 28)
                .onChange(of: code) { _, new in
                    let digits = String(new.filter(\.isNumber).prefix(Config.otpLength))
                    if digits != new { code = digits }
                    if digits.count == Config.otpLength { Task { await verify() } }
                }

            Button {
                Task { await verify() }
            } label: {
                busyLabel("Sign in")
            }
            .buttonStyle(.ketchup)
            .disabled(code.count != Config.otpLength || busy)
            .padding(.top, 16)

            HStack(spacing: 0) {
                Button("Different email") {
                    step = .email
                    code = ""
                    error = nil
                    notice = nil
                }
                .foregroundStyle(Theme.ink)
                Spacer(minLength: 16)
                Button(cooldown > 0 ? "Resend in \(cooldown)s" : "Resend code") {
                    Task { await sendCode() }
                }
                .monospacedDigit()
                .foregroundStyle(cooldown > 0 ? Theme.inkSoft : Theme.ketchupText)
                .disabled(busy || cooldown > 0)
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.plain)
            .padding(.top, 18)
            .padding(.horizontal, 4)
        }
    }

    /// A notice ("New code sent") or what went wrong, under the form.
    @ViewBuilder
    private var messages: some View {
        if let error {
            FormError(text: error)
        } else if let notice {
            Label(notice, systemImage: "checkmark.circle")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.pickle)
        }
    }

    private var byline: some View {
        Text("Summaries by \(Text(verbatim: Theme.modelName).fontWeight(.semibold)), Meta's model")
            .font(.footnote)
            .foregroundStyle(Theme.inkSoft)
            .frame(maxWidth: .infinity)
    }

    private func busyLabel(_ title: String) -> some View {
        ZStack {
            Text(title).opacity(busy ? 0 : 1)
            if busy { ProgressView().tint(Theme.onKetchup) }
        }
    }

    // MARK: Actions

    private func sendCode() async {
        guard validEmail, !busy, cooldown == 0 else { return }
        busy = true
        error = nil
        defer { busy = false }
        email = email.trimmingCharacters(in: .whitespaces).lowercased()
        let resending = step == .code
        do {
            try await Supabase.shared.sendCode(to: email)
            step = .code
            code = ""
            focused = true
            notice = resending ? "New code sent. Use the newest email." : nil
            startCooldown(60)
        } catch {
            self.error = error.localizedDescription
            // "…you can only request this after 22 seconds." → count that down.
            if let match = error.localizedDescription.firstMatch(of: /after (\d+) seconds/),
               let seconds = Int(match.1) {
                startCooldown(seconds)
            }
        }
    }

    private func startCooldown(_ seconds: Int) {
        cooldown = seconds
        Task {
            while cooldown > 0 {
                try? await Task.sleep(for: .seconds(1))
                cooldown -= 1
            }
        }
    }

    private func verify() async {
        guard code.count == Config.otpLength, !busy else { return }
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

#if DEBUG
extension SignInView {
    /// Offline preview: the code step for `email`, part of a code typed and
    /// the resend countdown running.
    init(previewCodeFor email: String, code: String, cooldown: Int) {
        _step = State(initialValue: .code)
        _email = State(initialValue: email)
        _code = State(initialValue: code)
        _cooldown = State(initialValue: cooldown)
    }
}
#endif
