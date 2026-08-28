import Foundation
import Combine
import OSLog
import SwiftData

@MainActor
final class StopWatchAudioPipelineService: ObservableObject {
    @Published private(set) var statusMessage: String?
    @Published private(set) var errorMessage: String?

    private let audioService: AudioRecorderService
    private let fileStore: AudioFileStore
    private let speechTranscriptionService: SpeechTranscriptionService
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "sheRuntime", category: "StopWatchAudioPipeline")
    private var processedURLs: Set<URL> = []
    private var processingTask: Task<Void, Never>?

    init(
        audioService: AudioRecorderService? = nil,
        fileStore: AudioFileStore? = nil,
        speechTranscriptionService: SpeechTranscriptionService? = nil
    ) {
        self.audioService = audioService ?? AudioRecorderService()
        self.fileStore = fileStore ?? AudioFileStore()
        self.speechTranscriptionService = speechTranscriptionService ?? SpeechTranscriptionService()
    }

    func handleCompletedStream(_ snapshot: StopWatchBLEService.StreamSnapshot, modelContext: ModelContext) {
        guard snapshot.isActive == false else { return }
        guard snapshot.result == "成功", let url = snapshot.recordingURL else {
            if snapshot.result?.hasPrefix("失败") == true {
                errorMessage = snapshot.result
            }
            return
        }
        guard processedURLs.insert(url).inserted else { return }

        processingTask?.cancel()
        processingTask = Task { [weak self] in
            await self?.process(url: url, elapsed: snapshot.elapsedSeconds ?? 0, modelContext: modelContext)
        }
    }

    private func process(url: URL, elapsed: TimeInterval, modelContext: ModelContext) async {
        errorMessage = nil
        statusMessage = C.t("dataPrivacy.audio.processing")

        do {
            let info = try await fileStore.inspect(url)
            guard info.sizeInBytes > 0 else {
                throw CocoaError(.fileReadCorruptFile)
            }

            try? audioService.play(url)
            _ = try await speechTranscriptionService.prepareChineseModel { [weak self] phase in
                switch phase {
                case .preparingModel:
                    self?.statusMessage = C.t("dataPrivacy.audio.preparing")
                case .transcribing:
                    self?.statusMessage = C.t("dataPrivacy.audio.transcribing")
                }
            }

            let transcript = try await speechTranscriptionService.transcribe(fileURL: url) { [weak self] phase in
                switch phase {
                case .preparingModel:
                    self?.statusMessage = C.t("dataPrivacy.audio.preparing")
                case .transcribing:
                    self?.statusMessage = C.t("dataPrivacy.audio.transcribing")
                }
            }
            let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                throw SpeechTranscriptionService.ServiceError.transcriptionFailed("未识别到语音内容")
            }

            let record = TimelineRecord(
                createdAt: Date(),
                eventType: TimelineRecordType.voiceCheckIn,
                rawTranscript: text,
                confirmedText: text,
                tags: VoiceReviewDraft.mockTags,
                recordingDuration: max(info.duration, elapsed),
                source: TimelineRecordSource.stopWatch,
                saveStatus: TimelineRecordStatus.saved
            )
            modelContext.insert(record)
            try modelContext.save()
            try? fileStore.delete(url)
            statusMessage = C.t("dataPrivacy.audio.saved")
            logger.info("StopWatch audio transcript saved")
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = nil
            logger.error("StopWatch audio pipeline failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
