import Combine
import Foundation
import OSLog

@MainActor
final class AudioProbeViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case requestingPermission
        case recording
        case inspecting
        case ready
        case playing
        case preparingTranscription
        case transcribing
        case error
    }

    @Published private(set) var state: State = .inspecting
    @Published private(set) var statusMessage = "正在检查保留的调试录音…"
    @Published private(set) var fileInfo: AudioFileInfo?
    @Published private(set) var errorMessage: String?
    @Published private(set) var transcript: String?
    @Published private(set) var transcriptionError: String?
    @Published private(set) var modelStatus: SpeechTranscriptionService.ModelStatus = .checking
    @Published private(set) var modelError: String?

    private let recorderService: AudioRecorderService
    private let fileStore: AudioFileStore
    private let speechTranscriptionService: SpeechTranscriptionService
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "sheRuntime", category: "AudioProbe")

    init() {
        let recorderService = AudioRecorderService()
        self.recorderService = recorderService
        fileStore = AudioFileStore()
        speechTranscriptionService = SpeechTranscriptionService()

        recorderService.onRecordingFinished = { [weak self] url, reason in
            Task { @MainActor [weak self] in await self?.recordingFinished(url: url, reason: reason) }
        }
        recorderService.onPlaybackFinished = { [weak self] in
            guard let self else { return }
            state = fileInfo == nil ? .idle : .ready
            statusMessage = "播放结束"
        }
        recorderService.onError = { [weak self] error in
            self?.showError(error)
        }

        Task { [weak self] in
            await self?.restoreMostRecentRecording()
        }
        Task { [weak self] in
            await self?.refreshModelStatus()
        }
    }

    private var isTranscriptionBusy: Bool {
        state == .preparingTranscription || state == .transcribing
    }

    var canRecord: Bool {
        state != .recording && state != .requestingPermission && state != .inspecting && !isTranscriptionBusy
    }
    var canStop: Bool { state == .recording }
    var canPlay: Bool { fileInfo != nil && (state == .ready || state == .error) && !isTranscriptionBusy }
    var canDelete: Bool {
        fileInfo != nil && state != .recording && state != .inspecting && !isTranscriptionBusy
    }
    var canTranscribe: Bool {
        fileInfo != nil && modelStatus == .installed &&
            (state == .ready || state == .error) && !isTranscriptionBusy
    }
    var canPrepareModel: Bool {
        !isTranscriptionBusy && modelStatus != .checking &&
            modelStatus != .installed && modelStatus != .downloading &&
            modelStatus != .unavailable
    }

    func startRecording() async {
        errorMessage = nil
        state = .requestingPermission
        statusMessage = "正在请求麦克风权限…"

        guard await recorderService.requestPermission() else {
            state = .error
            statusMessage = "麦克风权限未授权"
            errorMessage = "请在系统设置中允许 sheRuntime 使用麦克风后重试。"
            return
        }

        do {
            let url = try fileStore.makeRecordingURL()
            try recorderService.startRecording(to: url)
            state = .recording
            statusMessage = "正在录音，最长 10 秒…"
        } catch {
            showError(error)
        }
    }

    func stopRecording() {
        recorderService.stopRecording(reason: .user)
    }

    func play() {
        guard let url = fileInfo?.url, fileStore.exists(url) else {
            fileInfo = nil
            showError(CocoaError(.fileNoSuchFile))
            return
        }
        do {
            try recorderService.play(url)
            state = .playing
            statusMessage = "正在播放…"
        } catch {
            showError(error)
        }
    }

    func stopPlayback() {
        recorderService.stopPlayback()
    }

    func deleteCurrentRecording() {
        guard let url = fileInfo?.url else { return }
        recorderService.stopPlayback()
        do {
            try fileStore.delete(url)
            fileInfo = nil
            state = .idle
            statusMessage = "临时音频已删除"
            errorMessage = nil
            transcript = nil
            transcriptionError = nil
            logger.info("Temporary recording deleted: \(url.path, privacy: .public)")
            Task { [weak self] in
                await self?.restoreMostRecentRecording(afterDeletion: true)
            }
        } catch {
            showError(error)
        }
    }

    func handleBackground() {
        recorderService.stopRecording(reason: .background)
        recorderService.stopPlayback()
    }

    func viewDidDisappear() {
        recorderService.stopRecording(reason: .viewDismissed)
        recorderService.stopPlayback()
    }

    func transcribeCurrentRecording() async {
        guard let url = fileInfo?.url, canTranscribe else { return }
        transcript = nil
        transcriptionError = nil

        do {
            let text = try await speechTranscriptionService.transcribe(fileURL: url) {
                [weak self] phase in
                guard let self else { return }
                switch phase {
                case .preparingModel:
                    state = .preparingTranscription
                case .transcribing:
                    state = .transcribing
                }
            }
            transcript = text
            state = .ready
        } catch let error as SpeechTranscriptionService.ServiceError {
            handleSpeechServiceError(error)
            state = .error
        } catch {
            transcriptionError = error.localizedDescription
            state = .error
        }
    }

    func prepareChineseTranscriptionModel() async {
        guard canPrepareModel else { return }
        modelError = nil
        state = .preparingTranscription
        modelStatus = .downloading

        do {
            modelStatus = try await speechTranscriptionService.prepareChineseModel {
                [weak self] _ in
                self?.modelStatus = .downloading
                self?.state = .preparingTranscription
            }
            state = fileInfo == nil ? .idle : .ready
        } catch let error as SpeechTranscriptionService.ServiceError {
            let message = error.localizedDescription
            modelStatus = .failed(message)
            modelError = message
            state = .error
        } catch {
            modelStatus = .failed(error.localizedDescription)
            modelError = error.localizedDescription
            state = .error
        }
    }

    private func recordingFinished(url: URL, reason: AudioRecorderService.StopReason) async {
        state = .inspecting
        statusMessage = "正在检查录音文件…"
        transcript = nil
        transcriptionError = nil
        do {
            let info = try await fileStore.inspect(url)
            guard info.sizeInBytes > 0 else { throw CocoaError(.fileReadCorruptFile) }
            fileInfo = info
            state = .ready
            statusMessage = "录音已保存（\(reason.rawValue)）"
            errorMessage = reason == .user || reason == .durationLimit ? nil : "录音被中断，文件已保留用于调试。"
            logger.info("Recording saved: \(url.path, privacy: .public), \(info.sizeInBytes) bytes, \(info.duration) seconds")
        } catch {
            showError(error)
        }
    }

    private func restoreMostRecentRecording(afterDeletion: Bool = false) async {
        do {
            guard let url = try fileStore.mostRecentRecordingURL() else {
                state = .idle
                statusMessage = afterDeletion ? "临时音频已删除" : "尚未录音"
                return
            }
            let info = try await fileStore.inspect(url)
            guard info.sizeInBytes > 0 else { return }
            fileInfo = info
            state = .ready
            statusMessage = afterDeletion ? "已删除当前文件，显示上一条保留录音" : "已恢复保留的调试录音"
        } catch {
            showError(error)
        }
    }

    private func refreshModelStatus() async {
        modelStatus = .checking
        modelStatus = await speechTranscriptionService.currentModelStatus()
    }

    private func handleSpeechServiceError(
        _ error: SpeechTranscriptionService.ServiceError
    ) {
        let message = error.localizedDescription
        switch error {
        case .languageUnsupported:
            modelStatus = .unavailable
            modelError = message
        case .modelNotInstalled:
            modelStatus = .notInstalled
            modelError = message
        case .modelDownloading:
            modelStatus = .downloading
            modelError = message
        case .modelDownloadFailed:
            modelStatus = .failed(message)
            modelError = message
        case .fileNotFound, .transcriptionFailed:
            transcriptionError = message
        }
    }

    private func showError(_ error: Error) {
        state = .error
        statusMessage = "Audio Probe 出错"
        errorMessage = error.localizedDescription
        logger.error("Audio Probe error: \(error.localizedDescription, privacy: .public)")
    }
}
