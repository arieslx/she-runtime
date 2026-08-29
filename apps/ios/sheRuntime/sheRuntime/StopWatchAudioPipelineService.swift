import Foundation
import Combine
import OSLog
import SwiftData

@MainActor
final class StopWatchAudioPipelineService: ObservableObject {
    @Published private(set) var statusMessage: String?
    @Published private(set) var errorMessage: String?

    private let fileStore: AudioFileStore
    private let speechTranscriptionService: SpeechTranscriptionService
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "sheRuntime", category: "StopWatchAudioPipeline")
    private var processedURLs: Set<URL> = []
    private var processingTask: Task<Void, Never>?

    init(
        fileStore: AudioFileStore? = nil,
        speechTranscriptionService: SpeechTranscriptionService? = nil
    ) {
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

        let receivedAt = Date()
        processingTask?.cancel()
        processingTask = Task { [weak self] in
            await self?.process(
                url: url,
                elapsed: snapshot.elapsedSeconds ?? 0,
                receivedAt: receivedAt,
                modelContext: modelContext
            )
        }
    }

    private func process(
        url: URL,
        elapsed: TimeInterval,
        receivedAt: Date,
        modelContext: ModelContext
    ) async {
        errorMessage = nil
        statusMessage = C.t("dataPrivacy.audio.processing")
        // Audio is a transient transport for local transcription, not a retained sensor stream.
        defer { try? fileStore.delete(url) }
        var insertedRecord: TimelineRecord?

        do {
            let info = try await fileStore.inspect(url)
            guard info.sizeInBytes > 0 else {
                throw CocoaError(.fileReadCorruptFile)
            }

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
                // StopWatch's current transport does not include the original capture time.
                // Pin the event to receipt time rather than the later transcription finish time.
                createdAt: receivedAt,
                eventType: TimelineRecordType.voiceCheckIn,
                rawTranscript: text,
                confirmedText: text,
                tags: [],
                recordingDuration: max(info.duration, elapsed),
                source: TimelineRecordSource.stopWatch,
                saveStatus: TimelineRecordStatus.saved,
                confirmationStatus: .unreviewed,
                extractionStatus: .pending
            )
            modelContext.insert(record)
            insertedRecord = record
            try modelContext.save()
            statusMessage = C.t("dataPrivacy.audio.saved")
            logger.info("StopWatch audio transcript saved")
        } catch {
            if let insertedRecord {
                modelContext.delete(insertedRecord)
            }
            errorMessage = error.localizedDescription
            statusMessage = nil
            logger.error("StopWatch audio pipeline failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
