import AVFoundation
import Foundation
import Speech

actor SpeechTranscriptionService {
    enum Phase: Sendable {
        case preparingModel
        case transcribing
    }

    enum ServiceError: LocalizedError {
        case languageUnsupported
        case modelDownloadFailed(String)
        case fileNotFound
        case transcriptionFailed(String)

        var errorDescription: String? {
            switch self {
            case .languageUnsupported:
                "当前设备不支持简体中文端侧转写"
            case .modelDownloadFailed(let detail):
                "简体中文端侧模型下载失败：\(detail)"
            case .fileNotFound:
                "找不到要转写的临时录音文件"
            case .transcriptionFailed(let detail):
                "离线转写失败：\(detail)"
            }
        }
    }

    typealias PhaseHandler = @MainActor @Sendable (Phase) -> Void

    private let locale = Locale(identifier: "zh_CN")
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func transcribe(
        fileURL: URL,
        phaseHandler: PhaseHandler
    ) async throws -> String {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw ServiceError.fileNotFound
        }
        guard SpeechTranscriber.isAvailable,
              let supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw ServiceError.languageUnsupported
        }

        let transcriber = SpeechTranscriber(locale: supportedLocale, preset: .transcription)
        try await ensureModelInstalled(for: transcriber, phaseHandler: phaseHandler)
        await phaseHandler(.transcribing)

        do {
            let audioFile = try AVAudioFile(forReading: fileURL)
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            async let transcription = collectFinalizedText(from: transcriber)

            if let lastSample = try await analyzer.analyzeSequence(from: audioFile) {
                try await analyzer.finalizeAndFinish(through: lastSample)
            } else {
                await analyzer.cancelAndFinishNow()
            }

            let text = try await transcription
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                throw ServiceError.transcriptionFailed("未识别到语音内容")
            }
            return text
        } catch let error as ServiceError {
            throw error
        } catch {
            throw ServiceError.transcriptionFailed(error.localizedDescription)
        }
    }

    private func ensureModelInstalled(
        for transcriber: SpeechTranscriber,
        phaseHandler: PhaseHandler
    ) async throws {
        let modules: [any SpeechModule] = [transcriber]
        switch await AssetInventory.status(forModules: modules) {
        case .installed:
            return
        case .unsupported:
            throw ServiceError.languageUnsupported
        case .supported, .downloading:
            await phaseHandler(.preparingModel)
        @unknown default:
            await phaseHandler(.preparingModel)
        }

        do {
            guard let request = try await AssetInventory.assetInstallationRequest(
                supporting: modules
            ) else {
                guard await AssetInventory.status(forModules: modules) == .installed else {
                    throw ServiceError.modelDownloadFailed("系统未返回可用的模型安装请求")
                }
                return
            }
            try await request.downloadAndInstall()
            guard await AssetInventory.status(forModules: modules) == .installed else {
                throw ServiceError.modelDownloadFailed("模型安装完成后仍不可用")
            }
        } catch let error as ServiceError {
            throw error
        } catch {
            throw ServiceError.modelDownloadFailed(error.localizedDescription)
        }
    }

    private func collectFinalizedText(
        from transcriber: SpeechTranscriber
    ) async throws -> String {
        var finalizedText = ""
        for try await result in transcriber.results where result.isFinal {
            finalizedText += String(result.text.characters)
        }
        return finalizedText
    }
}
