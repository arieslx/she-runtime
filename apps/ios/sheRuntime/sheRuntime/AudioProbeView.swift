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
}

#Preview {
    NavigationStack { AudioProbeView() }
}
