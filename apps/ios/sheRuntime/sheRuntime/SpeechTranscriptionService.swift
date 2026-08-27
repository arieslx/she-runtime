import AVFoundation
import Foundation
import Speech

actor SpeechTranscriptionService {
    enum ModelStatus: Equatable, Sendable {
        case checking
        case installed
        case notInstalled
        case downloading
        case unavailable
        case failed(String)
    }

    enum Phase: Sendable {
        case preparingModel
        case transcribing
    }

    enum ServiceError: LocalizedError {
        case languageUnsupported
        case modelNotInstalled
        case modelDownloading
        case modelDownloadFailed(String)
        case fileNotFound
        case transcriptionFailed(String)

        var errorDescription: String? {
            switch self {
            case .languageUnsupported:
                "当前设备无法使用中文转写模型；录音已保留等待稍后转写。"
            case .modelNotInstalled:
                "中文转写模型尚未安装，请联网完成一次模型准备；录音已保留。"
            case .modelDownloading:
                "中文转写模型正在下载，请等待模型准备完成；录音已保留。"
            case .modelDownloadFailed(let detail):
                "中文转写模型尚未安装，请联网完成一次模型准备；录音已保留。下载失败：\(detail)"
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

    func currentModelStatus() async -> ModelStatus {
        guard let transcriber = await makeTranscriber() else { return .unavailable }
        return await modelStatus(for: transcriber)
    }

    func prepareChineseModel(
        phaseHandler: PhaseHandler
    ) async throws -> ModelStatus {
        guard let transcriber = await makeTranscriber() else {
            throw ServiceError.languageUnsupported
        }
        let modules: [any SpeechModule] = [transcriber]

        switch await AssetInventory.status(forModules: modules) {
        case .installed:
            return .installed
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
                return .installed
            }
            try await request.downloadAndInstall()
            guard await AssetInventory.status(forModules: modules) == .installed else {
                throw ServiceError.modelDownloadFailed("模型安装完成后仍不可用")
            }
            return .installed
        } catch let error as ServiceError {
            throw error
        } catch {
            throw ServiceError.modelDownloadFailed(error.localizedDescription)
        }
    }

    func transcribe(
        fileURL: URL,
        phaseHandler: PhaseHandler
    ) async throws -> String {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw ServiceError.fileNotFound
        }
        guard let transcriber = await makeTranscriber() else {
            throw ServiceError.languageUnsupported
        }
        switch await modelStatus(for: transcriber) {
        case .installed:
            break
        case .notInstalled:
            throw ServiceError.modelNotInstalled
        case .downloading, .checking:
            throw ServiceError.modelDownloading
        case .unavailable:
            throw ServiceError.languageUnsupported
        case .failed(let detail):
            throw ServiceError.modelDownloadFailed(detail)
        }
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

    private func makeTranscriber() async -> SpeechTranscriber? {
        guard SpeechTranscriber.isAvailable,
              let supportedLocale = await SpeechTranscriber.supportedLocale(
                equivalentTo: locale
              ) else {
            return nil
        }
        return SpeechTranscriber(locale: supportedLocale, preset: .transcription)
    }

    private func modelStatus(for transcriber: SpeechTranscriber) async -> ModelStatus {
        let modules: [any SpeechModule] = [transcriber]
        switch await AssetInventory.status(forModules: modules) {
        case .installed: return .installed
        case .supported: return .notInstalled
        case .downloading: return .downloading
        case .unsupported: return .unavailable
        @unknown default: return .unavailable
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
