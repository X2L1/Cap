import AVFoundation
import Foundation
import Speech

/// Tap-to-talk speech input via the Speech framework. This is a single live session you
/// start and stop — not push-to-talk per sentence. On-device recognition is requested
/// when the device supports it, so audio doesn't leave the phone where avoidable.
///
/// Requires NSSpeechRecognitionUsageDescription and NSMicrophoneUsageDescription in
/// Info.plist. No background-audio entitlement — this only runs while the app is open,
/// which matches the roadmap's honesty about iOS background-audio limits.
@MainActor
final class SpeechService: ObservableObject {
    @Published var isListening = false
    @Published var transcript = ""
    @Published var available = true

    private let recognizer = SFSpeechRecognizer()
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func requestAuthorization() async -> Bool {
        let speechOK = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
        let micOK = await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
        return speechOK && micOK
    }

    func start() throws {
        guard let recognizer, recognizer.isAvailable else {
            available = false
            return
        }
        // Tear down any prior run.
        stop()

        transcript = ""
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isListening = true

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    if result.isFinal { self.stop() }
                }
                if error != nil { self.stop() }
            }
        }
    }

    func stop() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isListening = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
