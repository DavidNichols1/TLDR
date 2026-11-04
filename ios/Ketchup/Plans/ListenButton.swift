//
//  ListenButton.swift
//  Ketchup
//
//  Pro's voice catch-up: the brief read aloud by the phone's own voice
//  (AVSpeechSynthesizer). Meta has no text to speech, so nothing new leaves
//  the phone and it costs nothing; it's on Pro as a pricing choice. Free and
//  Plus see it with a lock, and a tap shows the plans. Hidden until the
//  server has plans (migration 0010). One marked line in
//  AI/CatchUpContent.swift puts it under the byline.
//
//  The voice is the best English one installed: a premium voice (Settings >
//  Accessibility > Spoken Content > Voices) sounds close to natural, the
//  default one robotic. It's set by identifier, since on iOS 26 a lookup by
//  language can come back with the system default instead (FB20271264).
//

import AVFoundation
import SwiftUI

struct ListenButton: View {
    let brief: CatchUp
    /// The reader as the chat names them, read as "you".
    var readerName: String = ""

    @State private var speaker = BriefSpeaker.shared
    @State private var showPlans = false

    private var store: PlanStore { .shared }

    var body: some View {
        if store.available {
            let unlocked = store.status?.voice == true
            let speaking = speaker.reading == brief.tldr
            Button {
                if !unlocked {
                    showPlans = true
                } else if speaking {
                    speaker.stop()
                } else {
                    speaker.read(brief, readerName: readerName)
                }
            } label: {
                HStack(spacing: 6) {
                    // The speaker is the widest of the three, so it holds the icon's room.
                    Image(systemName: "speaker.wave.2.fill")
                        .hidden()
                        .overlay {
                            Image(systemName: !unlocked ? "lock.fill" : speaking ? "stop.fill" : "speaker.wave.2.fill")
                        }
                        .accessibilityHidden(true)
                    // Sized for "Listen" either way, so the button keeps its width.
                    Text("Listen")
                        .hidden()
                        .overlay(alignment: .leading) { Text(speaking ? "Stop" : "Listen") }
                    if !unlocked {
                        Text("Pro")
                            .font(.mono(.caption2, weight: .bold))
                            .textCase(.uppercase)
                            .foregroundStyle(Theme.inkSoft)
                    }
                }
            }
            .buttonStyle(.outline(.compact))
            .accessibilityHint(unlocked ? "Reads this catch-up aloud." : "Listening comes with Pro.")
            .sheet(isPresented: $showPlans) {
                PaywallSheet { showPlans = false }
            }
            .onDisappear {
                if speaking { speaker.stop() }
            }
        }
    }
}

/// Reads one catch-up at a time.
@Observable
final class BriefSpeaker: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = BriefSpeaker()

    /// The gist of the catch-up being read, while it's read.
    private(set) var reading: String?

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func read(_ brief: CatchUp, readerName: String) {
        stop()
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
        let utterance = AVSpeechUtterance(string: Self.script(brief, readerName: readerName))
        utterance.voice = Self.bestVoice()
        reading = brief.tldr
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        finished()
    }

    private func finished() {
        guard reading != nil else { return }
        reading = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in BriefSpeaker.shared.finished() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in BriefSpeaker.shared.finished() }
    }

    /// The gist, then what's for you, the plans, the money and what's still open.
    static func script(_ brief: CatchUp, readerName: String) -> String {
        let me = readerName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isMe = { (name: String) in !me.isEmpty && name.lowercased() == me }
        var lines = [brief.tldr]
        if !brief.forYou.isEmpty {
            lines.append("For you.")
            lines += brief.forYou.map(\.text)
        }
        if !brief.plans.isEmpty {
            lines.append("Plans.")
            lines += brief.plans.map { plan in
                [plan.title, plan.start?.formatted(.dateTime.weekday(.wide).hour().minute()), plan.location]
                    .compactMap { $0 }.joined(separator: ", ")
            }
        }
        if !brief.owes.isEmpty {
            lines.append("Money.")
            lines += brief.owes.map { owe in
                let who = isMe(owe.who) ? "You owe" : "\(owe.who) owes"
                let whom = owe.owesWhom.map { isMe($0) ? "you" : $0 } ?? "the group"
                return "\(who) \(whom) \(owe.what)"
            }
        }
        if !brief.openQuestions.isEmpty {
            lines.append("Still unanswered.")
            lines += brief.openQuestions.map(\.question)
        }
        return lines.map(sentence).filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func sentence(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last else { return "" }
        return ".!?".contains(last) ? trimmed : trimmed + "."
    }

    /// The best English voice installed, in the phone's own region if it has one.
    static func bestVoice() -> AVSpeechSynthesisVoice? {
        let wanted = AVSpeechSynthesisVoice.currentLanguageCode()
        let english = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language.hasPrefix("en") && !$0.voiceTraits.contains(.isNoveltyVoice) && !$0.voiceTraits.contains(.isPersonalVoice)
        }
        let local = english.filter { $0.language == wanted }
        let pool = local.isEmpty ? english : local
        guard let best = pool.max(by: { $0.quality.rawValue < $1.quality.rawValue }) else {
            return AVSpeechSynthesisVoice(language: wanted)
        }
        return AVSpeechSynthesisVoice(identifier: best.identifier) ?? best
    }
}
