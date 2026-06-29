import AVFoundation
import Foundation

/// Speaks Cap's replies aloud via AVSpeechSynthesizer, routed to whatever audio output is
/// active — wired or Bluetooth earbuds included for free through AVAudioSession. Pure
/// on-device synthesis; nothing leaves the phone.
@MainActor
final class SpeechSynthesizer: NSObject, ObservableObject {
    @Published var isSpeaking = false

    private let synth = AVSpeechSynthesizer()

    /// Best installed English voice. Premium > enhanced > default in quality, and a few
    /// named voices (Ava, Zoe, Evan…) are markedly more natural than the rest — so we
    /// prefer those when present. Premium/enhanced voices have to be downloaded by the user
    /// (Settings → Accessibility → Spoken Content → Voices); without one, only the robotic
    /// default exists, which is the real ceiling on how natural this can sound.
    private static let preferredVoice: AVSpeechSynthesisVoice? = {
        let english = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }
        let niceNames = ["ava", "zoe", "evan", "nathan", "joelle", "samantha"]
        func rank(_ v: AVSpeechSynthesisVoice) -> Int {
            var score = v.quality.rawValue * 10                       // premium(3) > enhanced(2) > default(1)
            if v.language == "en-US" { score += 3 }
            if niceNames.contains(where: { v.name.lowercased().contains($0) }) { score += 5 }
            return score
        }
        return english.max { rank($0) < rank($1) }
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
        // A hair slower than default reads more like a person than a GPS unit.
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.96
        utterance.pitchMultiplier = 1.0
        utterance.preUtteranceDelay = 0.05
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
