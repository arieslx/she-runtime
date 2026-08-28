import AVFoundation
import Combine
import Foundation
import Speech

@MainActor
final class AskSpeechInputViewModel: NSObject, ObservableObject {
    @Published private(set) var state: AskSpeechInputState = .idle
    @Published private(set) var recognizedText = ""
    @Published private(set) var errorKey: String?

    private let locale = Locale(identifier: "zh_CN")
    private var speechRecognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var baseText = ""
    private var userStopped = false

    override init() {
        speechRecognizer = SFSpeechRecognizer(locale: locale)
        super.init()
    }

    var isRecording: Bool {
        if case .recording = state { return true }
        return false
    }

    func toggle(currentText: String) async {
        if isRecording {
            stopRecording()
        } else {
            await startRecording(currentText: currentText)
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        userStopped = true
        stopAudioCapture()
        state = .idle
    }

    func cancelRecording() {
        userStopped = true
        stopAudioCapture()
        recognitionTask?.cancel()
        recognitionTask = nil
        state = .idle
    }

    private func startRecording(currentText: String) async {
#if os(iOS)
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            fail(with: "ask.speechUnavailable")
            return
        }

        let permissions = await requestPermissions()
        guard permissions else {
            fail(with: "ask.speechPermissionDenied")
            return
        }

        cancelRecognitionOnly()
        userStopped = false
        errorKey = nil
        baseText = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        recognizedText = currentText

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            // marktag: This live dictation path prioritizes compatibility. Depending on
            // device, locale, and system model availability, Apple may use network-backed
            // speech recognition; do not present it as fully local/private until privacy
            // copy and product policy are finalized.
            request.requiresOnDeviceRecognition = false
            recognitionRequest = request

            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1_024, format: recordingFormat) { buffer, _ in
                request.append(buffer)
            }

            recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor [weak self] in
                    self?.handleRecognition(result: result, error: error)
                }
            }

            audioEngine.prepare()
            try audioEngine.start()
            state = .recording
        } catch {
            fail(with: "ask.speechUnavailable")
        }
#else
        fail(with: "ask.speechUnavailable")
#endif
    }

    private func handleRecognition(
        result: SFSpeechRecognitionResult?,
        error: Error?
    ) {
        if let result {
            let transcript = result.bestTranscription.formattedString
                .trimmingCharacters(in: .whitespacesAndNewlines)
            recognizedText = mergedText(base: baseText, transcript: transcript)
            if result.isFinal {
                stopAudioCapture()
                state = .idle
            }
        }

        guard error != nil else { return }
        stopAudioCapture()
        if !userStopped {
            fail(with: "ask.speechUnavailable")
        } else {
            state = .idle
        }
    }

    private func mergedText(base: String, transcript: String) -> String {
        guard !base.isEmpty else { return transcript }
        guard !transcript.isEmpty else { return base }
        return "\(base) \(transcript)"
    }

    private func requestPermissions() async -> Bool {
#if os(iOS)
        async let speechAllowed = requestSpeechAuthorization()
        async let microphoneAllowed = AVAudioApplication.requestRecordPermission()
        let permissions = await (speechAllowed, microphoneAllowed)
        return permissions.0 && permissions.1
#else
        return false
#endif
    }

    private func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private func stopAudioCapture() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
#if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
#endif
    }

    private func cancelRecognitionOnly() {
        stopAudioCapture()
        recognitionTask?.cancel()
        recognitionTask = nil
    }

    private func fail(with key: String) {
        cancelRecognitionOnly()
        errorKey = key
        state = .failed(key)
    }
}

enum AskSpeechInputState: Equatable {
    case idle
    case recording
    case failed(String)
}
