import Foundation
import Combine
import SwiftData

@MainActor
final class VoiceCaptureViewModel: ObservableObject {
    @Published private(set) var state: VoiceCaptureState = .idle
    @Published private(set) var meterLevel: Double = 0

    private let recorderService: AudioRecorderService
    private let fileStore: AudioFileStore
    private let speechTranscriptionService: SpeechTranscriptionService
    private var meteringTimer: Timer?
    private var transcriptionTask: Task<Void, Never>?
    private var activeRecordingURL: URL?
    private var activeRecordingStartedAt: Date?
    private var resetTask: Task<Void, Never>?

    init(
        recorderService: AudioRecorderService? = nil,
        fileStore: AudioFileStore? = nil,
        speechTranscriptionService: SpeechTranscriptionService? = nil
    ) {
        let recorderService = recorderService ?? AudioRecorderService()
        self.recorderService = recorderService
        self.fileStore = fileStore ?? AudioFileStore()
        self.speechTranscriptionService = speechTranscriptionService ?? SpeechTranscriptionService()

        recorderService.onRecordingFinished = { [weak self] url, reason in
            Task { @MainActor [weak self] in
                self?.recordingFinished(url: url, reason: reason)
            }
        }

        recorderService.onError = { [weak self] error in
            Task { @MainActor [weak self] in
                self?.fail("录音出错：\(error.localizedDescription)", deleting: self?.activeRecordingURL)
            }
        }
    }

    func startRecording() async {
        guard state.canStartRecording else { return }
        resetTask?.cancel()
        transcriptionTask?.cancel()
        activeRecordingURL = nil
        activeRecordingStartedAt = nil
        meterLevel = 0
        state = .processing(message: "正在请求麦克风权限…")

        guard await recorderService.requestPermission() else {
            fail("麦克风权限未授权，请在系统设置中允许 sheRuntime 使用麦克风后重试。")
            return
        }

        do {
            let url = try fileStore.makeRecordingURL()
            let startedAt = Date()
            try recorderService.startRecording(to: url)
            activeRecordingURL = url
            activeRecordingStartedAt = startedAt
            state = .recording(startedAt: startedAt)
            startMetering()
        } catch {
            fail("录音启动失败：\(error.localizedDescription)", deleting: activeRecordingURL)
        }
    }

    func stopRecordingAndTranscribe() {
        guard case .recording = state else { return }
        state = .processing(message: "正在保存录音…")
        stopMetering()
        recorderService.stopRecording(reason: .user)
    }

    func cancelRecording() {
        guard case .recording = state else { return }
        stopMetering()
        state = .idle
        recorderService.stopRecording(reason: .viewDismissed)
        activeRecordingURL = nil
        activeRecordingStartedAt = nil
    }

    func updateDraftText(_ text: String) {
        guard case .reviewing(var draft) = state else { return }
        draft.confirmedText = text
        state = .reviewing(draft)
    }

    func cancelReview() {
        guard case .reviewing(let draft) = state else {
            cancelActiveFlow()
            return
        }
        cleanupTemporaryAudio(draft.recordingURL)
        activeRecordingURL = nil
        activeRecordingStartedAt = nil
        state = .idle
    }

    func saveReviewedVoiceRecord(modelContext: ModelContext) {
        guard case .reviewing(let draft) = state else { return }
        let finalText = draft.confirmedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !finalText.isEmpty else {
            fail("没有可保存的转写内容", deleting: draft.recordingURL)
            return
        }

        let record = TimelineRecord(
            createdAt: Date(),
            eventType: TimelineRecordType.voiceCheckIn,
            rawTranscript: draft.rawTranscript,
            confirmedText: finalText,
            tags: draft.tags,
            recordingDuration: draft.recordingDuration,
            source: TimelineRecordSource.iPhoneVoice,
            saveStatus: TimelineRecordStatus.saved
        )
        modelContext.insert(record)

        do {
            try modelContext.save()
            cleanupTemporaryAudio(draft.recordingURL)
            activeRecordingURL = nil
            activeRecordingStartedAt = nil
            state = .saved
            scheduleIdleReset(after: 2)
        } catch {
            modelContext.delete(record)
            fail("保存失败：\(error.localizedDescription)", deleting: draft.recordingURL)
        }
    }

    func handleSceneInactive() {
        switch state {
        case .recording:
            stopMetering()
            recorderService.stopRecording(reason: .background)
        case .processing:
            transcriptionTask?.cancel()
            fail("处理已中断：App 进入后台", deleting: activeRecordingURL)
        case .reviewing(let draft):
            cleanupTemporaryAudio(draft.recordingURL)
            state = .idle
        case .idle, .saved, .failed:
            break
        }
    }

    func handleVoiceSurfaceDismissed() {
        switch state {
        case .recording:
            stopMetering()
            recorderService.stopRecording(reason: .viewDismissed)
        case .processing:
            transcriptionTask?.cancel()
            fail("处理已取消", deleting: activeRecordingURL)
        case .reviewing(let draft):
            cleanupTemporaryAudio(draft.recordingURL)
            state = .idle
        case .idle, .saved, .failed:
            break
        }
    }

    private func recordingFinished(url: URL, reason: AudioRecorderService.StopReason) {
        stopMetering()

        guard state.isAwaitingRecordingFile else {
            cleanupTemporaryAudio(url)
            return
        }

        guard reason == .user || reason == .durationLimit else {
            fail("录音已中断：\(reason.rawValue)", deleting: url)
            return
        }

        let startedAt = activeRecordingStartedAt ?? Date()
        let elapsed = max(0, Date().timeIntervalSince(startedAt))
        activeRecordingURL = url
        state = .processing(message: "正在检查录音…")

        transcriptionTask = Task { [weak self] in
            await self?.inspectAndTranscribe(url: url, elapsed: elapsed)
        }
    }

    private func inspectAndTranscribe(url: URL, elapsed: TimeInterval) async {
        do {
            let info = try await fileStore.inspect(url)
            guard info.sizeInBytes > 0 else {
                throw VoiceCaptureError.emptyRecording
            }

            let duration = max(info.duration, elapsed)
            guard duration >= 0.8 else {
                throw VoiceCaptureError.tooShort
            }

            state = .processing(message: "正在准备端侧中文模型…")
            _ = try await speechTranscriptionService.prepareChineseModel { [weak self] phase in
                guard let self else { return }
                switch phase {
                case .preparingModel:
                    self.state = .processing(message: "正在准备端侧中文模型…")
                case .transcribing:
                    self.state = .processing(message: "正在设备端转写…")
                }
            }

            guard !Task.isCancelled else { throw CancellationError() }
            state = .processing(message: "正在设备端转写…")
            let transcript = try await speechTranscriptionService.transcribe(fileURL: url) { [weak self] phase in
                guard let self else { return }
                switch phase {
                case .preparingModel:
                    self.state = .processing(message: "正在准备端侧中文模型…")
                case .transcribing:
                    self.state = .processing(message: "正在设备端转写…")
                }
            }

            guard !Task.isCancelled else { throw CancellationError() }
            let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                throw VoiceCaptureError.noTranscript
            }

            state = .reviewing(
                VoiceReviewDraft(
                    rawTranscript: text,
                    confirmedText: text,
                    tags: VoiceReviewDraft.mockTags,
                    recordingDuration: duration,
                    recordingURL: url
                )
            )
        } catch is CancellationError {
            cleanupTemporaryAudio(url)
            state = .idle
        } catch {
            fail(error.localizedDescription, deleting: url)
        }
    }

    private func cancelActiveFlow() {
        transcriptionTask?.cancel()
        stopMetering()
        recorderService.stopRecording(reason: .viewDismissed)
        cleanupTemporaryAudio(activeRecordingURL)
        activeRecordingURL = nil
        activeRecordingStartedAt = nil
        state = .idle
    }

    private func startMetering() {
        meteringTimer?.invalidate()
        meteringTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let target = self.recorderService.normalizedPowerLevel()
                let response = target > self.meterLevel ? 0.58 : 0.24
                self.meterLevel += (target - self.meterLevel) * response
            }
        }
    }

    private func stopMetering() {
        meteringTimer?.invalidate()
        meteringTimer = nil
        meterLevel = 0
    }

    private func fail(_ message: String, deleting url: URL? = nil) {
        stopMetering()
        transcriptionTask?.cancel()
        cleanupTemporaryAudio(url)
        activeRecordingURL = nil
        activeRecordingStartedAt = nil
        state = .failed(message)
        scheduleIdleReset(after: 2.6)
    }

    private func scheduleIdleReset(after seconds: TimeInterval) {
        resetTask?.cancel()
        resetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self else { return }
            switch self.state {
            case .saved, .failed:
                self.state = .idle
            case .idle, .recording, .processing, .reviewing:
                break
            }
        }
    }

    private func cleanupTemporaryAudio(_ url: URL?) {
        guard let url else { return }
        try? fileStore.delete(url)
    }
}

enum VoiceCaptureState: Equatable {
    case idle
    case recording(startedAt: Date)
    case processing(message: String)
    case reviewing(VoiceReviewDraft)
    case saved
    case failed(String)

    var animationKey: String {
        switch self {
        case .idle:
            "idle"
        case .recording:
            "recording"
        case .processing:
            "processing"
        case .reviewing:
            "reviewing"
        case .saved:
            "saved"
        case .failed:
            "failed"
        }
    }

    var canStartRecording: Bool {
        if case .idle = self { return true }
        return false
    }

    var isAwaitingRecordingFile: Bool {
        switch self {
        case .recording, .processing:
            true
        case .idle, .reviewing, .saved, .failed:
            false
        }
    }
}

struct VoiceReviewDraft: Equatable {
    static let mockTags = ["Work", "Meeting", "Mental fatigue", "Energy ↓"]

    var rawTranscript: String
    var confirmedText: String
    var tags: [String]
    var recordingDuration: TimeInterval
    var recordingURL: URL?
}

private enum VoiceCaptureError: LocalizedError {
    case emptyRecording
    case tooShort
    case noTranscript

    var errorDescription: String? {
        switch self {
        case .emptyRecording:
            "录音文件为空，请重试。"
        case .tooShort:
            "录音时间太短，请至少说一小段内容。"
        case .noTranscript:
            "没有识别到文本，请重试。"
        }
    }
}
