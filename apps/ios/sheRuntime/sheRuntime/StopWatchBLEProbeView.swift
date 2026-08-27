import SwiftUI

struct StopWatchBLEProbeView: View {
    @StateObject private var viewModel = StopWatchBLEProbeViewModel()

    var body: some View {
        List {
            Section("状态") {
                LabeledContent("蓝牙", value: viewModel.bluetoothState)
                LabeledContent("流程", value: viewModel.status)
                LabeledContent("Command 可写", value: viewModel.isWritable ? "是" : "否")
                LabeledContent("Response 已订阅", value: viewModel.isSubscribed ? "是" : "否")

                if let error = viewModel.errorMessage {
                    Text(error).foregroundStyle(.red).textSelection(.enabled)
                }
            }

            Section("发现的设备") {
                if let name = viewModel.discoveredName {
                    LabeledContent("名称", value: name)
                    LabeledContent("RSSI", value: "\(viewModel.rssi ?? 0) dBm")
                } else {
                    Text("尚未发现设备").foregroundStyle(.secondary)
                }
            }

            Section("操作") {
                Button("扫描 StopWatch") { viewModel.scan() }
                Button("连接 StopWatch") { viewModel.connect() }
                    .disabled(!viewModel.canConnect)
                Button("发送 ping") { viewModel.sendPing() }
                    .disabled(!viewModel.canSendPing)
                Button("开始真实麦克风音频流") { viewModel.startStreamTest() }
                    .disabled(!viewModel.canStartStream)
                Button("播放录音") { viewModel.playRecording() }
                    .disabled(!viewModel.canPlayRecording)
                Button("主动断开", role: .destructive) { viewModel.disconnect() }
                    .disabled(!viewModel.isConnected)
            }

            Section("真实麦克风 ADPCM 音频流") {
                LabeledContent("当前 MTU", value: mtuText)
                LabeledContent("实际 Notify 帧长度", value: notifyLengthText)
                LabeledContent("sessionId", value: transferIdText)
                LabeledContent(
                    "payload bytes（已收/预期）",
                    value: "\(viewModel.stream.receivedPayloadBytes) / \(viewModel.stream.expectedPayloadBytes)"
                )
                LabeledContent(
                    "帧数（已收/预期）",
                    value: "\(viewModel.stream.receivedFrames) / \(viewModel.stream.expectedFrames)"
                )
                LabeledContent(
                    "当前 sequence",
                    value: viewModel.stream.currentSequence.map(String.init) ?? "—"
                )
                LabeledContent("缺失帧", value: "\(viewModel.stream.missingFrames)")
                LabeledContent("重复帧", value: "\(viewModel.stream.duplicateFrames)")
                LabeledContent("预期 CRC32", value: crcText(viewModel.stream.expectedCRC32))
                LabeledContent("实际 CRC32", value: crcText(viewModel.stream.actualCRC32))
                LabeledContent("解码峰值", value: pcmPeakText)
                LabeledContent("解码 RMS", value: pcmRMSText)
                LabeledContent("总耗时", value: elapsedText)
                LabeledContent("传输速度", value: speedText)
                LabeledContent("已发送 RECEIVED", value: viewModel.stream.confirmationSent ? "是" : "否")
                LabeledContent("最终结果", value: viewModel.stream.result ?? "尚未测试")
            }

            if let response = viewModel.responseText {
                Section("响应") {
                    LabeledContent("文本", value: response)
                    if let milliseconds = viewModel.roundTripMilliseconds {
                        LabeledContent(
                            "往返耗时",
                            value: milliseconds.formatted(.number.precision(.fractionLength(1))) + " ms"
                        )
                    }
                }
            }
        }
        .navigationTitle("BLE Probe")
        .onDisappear { viewModel.stopScanning() }
    }

    private var transferIdText: String {
        viewModel.stream.sessionId.map(String.init) ?? "—"
    }

    private var mtuText: String {
        guard let length = viewModel.stream.notifyLength else { return "由固件串口确认" }
        return length == 174 ? "至少 177（由 174-byte Notify 验证）" : "不足"
    }

    private var notifyLengthText: String {
        viewModel.stream.notifyLength.map { "\($0) bytes" } ?? "—"
    }

    private var elapsedText: String {
        guard let elapsed = viewModel.stream.elapsedSeconds else { return "—" }
        return elapsed.formatted(.number.precision(.fractionLength(2))) + " s"
    }

    private var speedText: String {
        guard let speed = viewModel.stream.speedKBPerSecond else { return "—" }
        return speed.formatted(.number.precision(.fractionLength(2))) + " KB/s"
    }

    private var pcmPeakText: String {
        guard let peak = viewModel.stream.decodedPeak else { return "—" }
        return "\(peak) / 32767"
    }

    private var pcmRMSText: String {
        guard let rms = viewModel.stream.decodedRMS else { return "—" }
        return rms.formatted(.number.precision(.fractionLength(1)))
    }

    private func crcText(_ crc: UInt32?) -> String {
        guard let crc else { return "—" }
        return String(format: "0x%08X", crc)
    }
}

#Preview {
    NavigationStack { StopWatchBLEProbeView() }
}
