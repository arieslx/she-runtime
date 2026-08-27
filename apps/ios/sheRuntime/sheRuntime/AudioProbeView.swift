import SwiftUI

struct AudioProbeView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel = AudioProbeViewModel()

    var body: some View {
        List {
            Section("状态") {
                LabeledContent("录音状态", value: viewModel.statusMessage)

                if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("audioProbeError")
                }
            }

            Section("临时文件") {
                if let info = viewModel.fileInfo {
                    LabeledContent("时长", value: info.duration.formatted(.number.precision(.fractionLength(2))) + " 秒")
                    LabeledContent("大小", value: ByteCountFormatter.string(fromByteCount: info.sizeInBytes, countStyle: .file))
                    Text(info.url.path)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                } else {
                    Text("暂无音频文件")
                        .foregroundStyle(.secondary)
                }
            }

            Section("操作") {
                Button("开始录音") {
                    Task { await viewModel.startRecording() }
                }
                .disabled(!viewModel.canRecord)

                Button("停止录音") {
                    viewModel.stopRecording()
                }
                .disabled(!viewModel.canStop)

                if viewModel.state == .playing {
                    Button("停止播放") { viewModel.stopPlayback() }
                } else {
                    Button("播放刚才的录音") { viewModel.play() }
                        .disabled(!viewModel.canPlay)
                }

                Button("删除当前临时音频", role: .destructive) {
                    viewModel.deleteCurrentRecording()
                }
                .disabled(!viewModel.canDelete)

                if viewModel.fileInfo != nil {
                    Button("离线转写当前录音") {
                        Task { await viewModel.transcribeCurrentRecording() }
                    }
                    .disabled(!viewModel.canTranscribe)
                }
            }

            Section("中文本地模型") {
                LabeledContent("本地模型状态", value: modelStatusText)

                Button("准备中文转写模型") {
                    Task { await viewModel.prepareChineseTranscriptionModel() }
                }
                .disabled(!viewModel.canPrepareModel)

                if let error = viewModel.modelError {
                    Text(error)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("modelError")
                }
            }

            if viewModel.state == .preparingTranscription ||
                viewModel.state == .transcribing ||
                viewModel.transcript != nil ||
                viewModel.transcriptionError != nil {
                Section("离线转写状态") {
                    if viewModel.state == .preparingTranscription {
                        HStack {
                            ProgressView()
                            Text("正在准备简体中文端侧模型，首次使用可能需要下载…")
                        }
                    } else if viewModel.state == .transcribing {
                        HStack {
                            ProgressView()
                            Text("正在设备端转写录音…")
                        }
                    } else if viewModel.transcript != nil {
                        Text("离线转写完成")
                    }

                    if let error = viewModel.transcriptionError {
                        Text(error)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("transcriptionError")
                    }
                }
            }

            if let transcript = viewModel.transcript {
                Section("转写结果") {
                    Text(transcript)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("transcriptText")
                }
            }

            Section {
                Text("重新录音不会自动删除旧音频。当前阶段仅在你明确点击删除后移除文件；后续接入转写时，再改为文字确认成功后自动删除。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Audio Probe")
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { viewModel.handleBackground() }
        }
        .onDisappear { viewModel.viewDidDisappear() }
    }

    private var modelStatusText: String {
        switch viewModel.modelStatus {
        case .checking:
            "正在检查…"
        case .installed:
            "已安装，可以立即离线转写"
        case .notInstalled:
            "未安装，需要联网下载"
        case .downloading:
            "正在下载"
        case .unavailable:
            "不可用；录音将保留等待稍后转写"
        case .failed:
            "下载失败"
        }
    }
}

#Preview {
    NavigationStack { AudioProbeView() }
}
