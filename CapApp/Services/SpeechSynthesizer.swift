import AVFoundation
import Foundation

/// Speaks Cap's replies aloud via AVSpeechSynthesizer, routed to whatever audio output is
/// active — wired or Bluetooth earbuds included for free through AVAudioSession. Pure
/// on-device synthesis; nothing leaves the phone.
@MainActor
final class SpeechSynthesizer: NSObject, ObservableObject {
    @Published var isSpeaking = false

    private let synth = AVSpeechSynthesizer()

    /// Best installed English voice. Enhanced/premium voices (downloaded via Settings →
    /// Accessibility → Spoken Content → Voices) sound far less robotic; we fall back to
    /// whatever's there. Resolved once — scanning every speak() call is wasteful.
    private static let preferredVoice: AVSpeechSynthesisVoice? = {
        let english = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }
        let ranked = english.sorted { $0.quality.rawValue > $1.quality.rawValue }
        return ranked.first(where: { $0.language == "en-US" }) ?? ranked.first
    }()

    override init() {
        super.init()
        synth.delegate = self
    }

    func speak(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        // Route to earbuds/speaker and activate the session BEFORE speaking, so the first
        // syllable doesn't get clipped while the audio route spins up.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .allowBluetoothA2DP])
        try? session.setActive(true)

        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.preferredVoice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synth.speak(utterance)
    }

    func stop() {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
    }
}

extension SpeechSynthesizer: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = true }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
}
