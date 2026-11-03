//
//  AIConsentSheet.swift
//  Ketchup
//
//  Asked once, before your first catch-up or question: Ketchup sends the
//  messages it covers, your friends' included, to Meta's Muse Spark, and
//  Muse Spark is for people 18 and older. Apple's guideline 5.1.2(i) wants
//  that said plainly with an explicit yes; Meta's terms (section 10.1) want
//  the age. The yes is kept with your account (ai_consents, migration 0010),
//  and the server refuses a catch-up without it.
//

import SwiftUI

struct AIConsentSheet: View {
    /// True: allowed (and 18 or older). False: not now.
    let answer: (Bool) -> Void

    @State private var adult = false
    @ScaledMetric(relativeTo: .largeTitle) private var dropSize: CGFloat = 40

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                points
                ageCheck
                VStack(spacing: 12) {
                    Button("Allow and continue") { answer(true) }
                        .buttonStyle(.ketchup)
                        .disabled(!adult)
                    Button("Not now") { answer(false) }
                        .buttonStyle(.outline)
                }
                Text("You're asked once. Your answer is kept with your Ketchup account.")
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSoft)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 32)
        }
        .background(Theme.cream)
        .presentationBackground(Theme.cream)
        .sensoryFeedback(.selection, trigger: adult)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Kicker("Before your first catch-up")
                Text("\(Theme.modelName) reads it for you")
                    .font(.serif(.largeTitle))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 0)
            KetchupDrop()
                .fill(Theme.ketchup)
                .frame(width: dropSize, height: dropSize)
                .rotationEffect(.degrees(-8))
                .accessibilityHidden(true)
        }
    }

    private var points: some View {
        VStack(alignment: .leading, spacing: 0) {
            point("text.bubble",
                  "To write a catch-up or answer a question, Ketchup sends the messages it covers to Meta's \(Theme.modelName). That includes your friends' messages in the chat.")
            SettingsHairline()
            point("lock",
                  "Ketchup uses Meta's Standard mode, and Meta doesn't train its AI on them.")
            SettingsHairline()
            point("person.crop.circle.badge.checkmark",
                  "\(Theme.modelName) is for people 18 and older.")
        }
        .paperCard(padding: 0)
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        SettingsRow(text, systemImage: symbol)
    }

    /// The age, said explicitly: an ink check, like Report's choices.
    private var ageCheck: some View {
        Button {
            adult.toggle()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: adult ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(Theme.ink)
                    .accessibilityHidden(true)
                Text("I'm 18 or older")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 0)
            }
            .padding(16)
            .paperCard(padding: 0)
            .contentShape(.rect)
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(adult ? .isSelected : [])
        .accessibilityHint("Allow and continue needs this checked.")
    }
}
