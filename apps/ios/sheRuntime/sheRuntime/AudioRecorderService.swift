import AVFoundation
import Foundation
import OSLog

@MainActor
final class AudioRecorderService: NSObject {
    enum StopReason: String {
        case user = "用户停止"
        case durationLimit = "达到 10 秒上限"
        case background = "App 进入后台"
        case viewDismissed = "页面退出"
        case interruption = "音频会话被中断"
    }

    enum ServiceError: LocalizedError {
        case recordingUnavailable
        case recordingFailed

        var errorDescription: String? {
            switch self {
            case .recordingUnavailable:
                "当前平台不支持 Audio Probe 录音"
            case .recordingFailed:
                "录音未能启动"
            }
        }
    }

    var onRecordingFinished: ((URL, StopReason) -> Void)?
    var onPlaybackFinished: (() -> Void)?
    var onError: ((Error) -> Void)?

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "sheRuntime", category: "AudioProbe")
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var durationTimer: Timer?
    private var interruptionObserver: NSObjectProtocol?

    override init() {
        super.init()
#if os(iOS)
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.stopRecording(reason: .interruption)
                self?.stopPlayback()
            }
        }
#endif
    }

    deinit {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
    }

    func requestPermission() async -> Bool {
        logger.info("Requesting microphone permission")
#if os(iOS)
        let granted = await AVAudioApplication.requestRecordPermission()
        logger.info("Microphone permission result: \(granted, privacy: .public)")
        return granted
#else
        return false
#endif
    }

    func startRecording(to url: URL) throws {
#if os(iOS)
        stopPlayback()
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
        try session.setActive(true)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            AVEncoderBitRateKey: 96_000,
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.delegate = self
        recorder.isMeteringEnabled = true
        recorder.prepareToRecord()

        guard recorder.record() else {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw ServiceError.recordingFailed
        }

        self.recorder = recorder
        durationTimer?.invalidate()
        durationTimer = Timer.scheduledTimer(withTimeInterval: 10.1, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.stopRecording(reason: .durationLimit)
            }
        }
        logger.info("Recording started: \(url.path, privacy: .public)")
#else
        throw ServiceError.recordingUnavailable
#endif
    }

    func stopRecording(reason: StopReason) {
        guard let recorder, recorder.isRecording else { return }
        durationTimer?.invalidate()
        durationTimer = nil
        let url = recorder.url
        recorder.stop()
        self.recorder = nil
#if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
#endif
        logger.info("Recording stopped (\(reason.rawValue, privacy: .public)): \(url.path, privacy: .public)")
        onRecordingFinished?(url, reason)
    }

    func play(_ url: URL) throws {
#if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio)
        try session.setActive(true)
#endif
        let player = try AVAudioPlayer(contentsOf: url)
        player.delegate = self
        player.prepareToPlay()
        guard player.play() else { throw ServiceError.recordingFailed }
        self.player = player
        logger.info("Playback started: \(url.path, privacy: .public)")
    }

    func stopPlayback() {
        guard let player else { return }
        player.stop()
        self.player = nil
#if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
#endif
        logger.info("Playback stopped")
        onPlaybackFinished?()
    }
}

extension AudioRecorderService: AVAudioRecorderDelegate, AVAudioPlayerDelegate {
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        guard let error else { return }
        Task { @MainActor [weak self] in self?.onError?(error) }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            self?.player = nil
#if os(iOS)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
#endif
            self?.logger.info("Playback finished; success: \(flag, privacy: .public)")
            self?.onPlaybackFinished?()
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        guard let error else { return }
        Task { @MainActor [weak self] in self?.onError?(error) }
    }
}
