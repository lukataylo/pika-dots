import AVFoundation
import Speech

/// Push-to-talk dictation for the purpose pill. Recognition runs on-device when the Mac
/// supports it; audio is never stored or sent anywhere by Pika.
@MainActor
final class VoiceInput {
    static let shared = VoiceInput()
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var timer: Task<Void, Never>?
    private var finish: ((String) -> Void)?
    private var onListening: ((Bool) -> Void)?
    private var latest = ""
    private var startedAt = Date()
    private(set) var listening = false

    func start(partial: @escaping (String) -> Void, final: @escaping (String) -> Void,
               listening onListening: @escaping (Bool) -> Void, failure: @escaping (String) -> Void) {
        if listening { stop(); return }
        Task {
            guard await Self.authorize() else { failure("Allow Microphone and Speech Recognition for Pika Dots in System Settings."); return }
            guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else { failure("Speech recognition is unavailable right now."); return }
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
            Self.installTap(on: engine.inputNode, feeding: request)
            do { engine.prepare(); try engine.start() } catch {
                engine.inputNode.removeTap(onBus: 0)
                failure("Couldn’t start the microphone."); return
            }
            self.request = request; finish = final; self.onListening = onListening
            latest = ""; startedAt = Date(); listening = true; onListening(true)
            task = Self.recognize(recognizer, request) { [weak self] text, done in
                guard let self, self.listening else { return }
                if let text { self.latest = text; partial(text); self.armTimer() }
                if done { self.stop() }
            }
            armTimer(silence: 6)
        }
    }

    /// Stops after a pause in speech, or after 30s in total.
    private func armTimer(silence: Double = 1.6) {
        timer?.cancel()
        let wait = min(silence, max(0, 30 - Date().timeIntervalSince(startedAt)))
        timer = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(wait)) } catch { return }
            self?.stop()
        }
    }

    func stop() {
        guard listening else { return }
        listening = false; onListening?(false)
        timer?.cancel(); engine.stop(); engine.inputNode.removeTap(onBus: 0)
        request?.endAudio(); task?.cancel()
        let text = latest.trimmingCharacters(in: .whitespacesAndNewlines), done = finish
        finish = nil; onListening = nil; request = nil; task = nil
        if !text.isEmpty { done?(text) }
    }

    // Nonisolated so the audio and recognition callbacks, which arrive on background
    // queues, never inherit main-actor isolation.
    nonisolated private static func installTap(on input: AVAudioInputNode, feeding request: SFSpeechAudioBufferRecognitionRequest) {
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in request.append(buffer) }
    }
    nonisolated private static func recognize(_ recognizer: SFSpeechRecognizer, _ request: SFSpeechAudioBufferRecognitionRequest,
                                              update: @escaping @MainActor (String?, Bool) -> Void) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            let text = result?.bestTranscription.formattedString
            let done = error != nil || result?.isFinal == true
            Task { @MainActor in update(text, done) }
        }
    }
    nonisolated private static func authorize() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        guard speech else { return false }
        return await AVCaptureDevice.requestAccess(for: .audio)
    }
}
