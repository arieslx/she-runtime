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
                Button("主动断开", role: .destructive) { viewModel.disconnect() }
                    .disabled(!viewModel.isConnected)
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
}

#Preview {
    NavigationStack { StopWatchBLEProbeView() }
}
