@preconcurrency import AVFoundation
import Observation
@preconcurrency import Speech

/// Hold the mic to talk to the coach: speech to text, on the iPhone where it can be.
@Observable
@MainActor
final class SpeechInput {
    private(set) var text = ""
    private(set) var listening = false
    private(set) var denied = false

    @ObservationIgnored private let recognizer = SFSpeechRecognizer()
    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?

    func start() {
        guard !listening else { return }
        text = ""
        listening = true
        Task {
            let speech = await withCheckedContinuation { done in
                SFSpeechRecognizer.requestAuthorization { done.resume(returning: $0) }
            }
            let mic = await AVAudioApplication.requestRecordPermission()
            guard speech == .authorized, mic, listening else {
                denied = speech != .authorized || !mic
                listening = false
                return
            }
            begin()
        }
    }

    /// Stops and returns what was heard.
    @discardableResult
    func stop() -> String {
        listening = false
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        request = nil
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return text
    }

    private func begin() {
        guard let recognizer, recognizer.isAvailable else { listening = false; return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        request.contextualStrings = ["sets", "reps", "pulldown", "deadlift", "RDL", "kilos", "pounds"]
        self.request = request
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            Self.feed(engine.inputNode, to: request)
            engine.prepare()
            try engine.start()
        } catch {
            listening = false
            return
        }
        task = Self.recognize(request, with: recognizer) { [weak self] heard in self?.text = heard }
    }

    // The audio tap and the recognizer call back on their own threads, so their closures are
    // made outside the main actor.
    nonisolated private static func feed(_ input: AVAudioInputNode, to request: SFSpeechAudioBufferRecognitionRequest) {
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
            request.append(buffer)
        }
    }

    nonisolated private static func recognize(_ request: SFSpeechAudioBufferRecognitionRequest, with recognizer: SFSpeechRecognizer,
                                              heard: @escaping @MainActor @Sendable (String) -> Void) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, _ in
            guard let text = result?.bestTranscription.formattedString else { return }
            Task { @MainActor in heard(text) }
        }
    }
}
