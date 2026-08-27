import SwiftUI

struct HealthKitProbeView: View {
    @StateObject private var viewModel = HealthKitProbeViewModel()

    var body: some View {
        List {
            statusSection

            Section("身体数据") {
                LabeledContent("今日步数") { optionalText(viewModel.stepCount.map(String.init)) }
                LabeledContent("最新 HRV") {
                    optionalText(viewModel.latestHRV.map {
                        $0.valueMilliseconds.formatted(.number.precision(.fractionLength(1))) + " ms"
                    })
                }
                LabeledContent("静息心率") {
                    optionalText(viewModel.latestRestingHeartRate.map {
                        $0.valueBPM.formatted(.number.precision(.fractionLength(1))) + " bpm"
                    })
                }
            }

            Section("最近一次主要睡眠") {
                if let sleep = viewModel.sleepSummary {
                    LabeledContent("开始", value: sleep.startDate.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("结束", value: sleep.endDate.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("总睡眠", value: durationText(sleep.totalSleepDuration))
                    LabeledContent("Core", value: stageDurationText(sleep.duration(for: .core)))
                    LabeledContent("Deep", value: stageDurationText(sleep.duration(for: .deep)))
                    LabeledContent("REM", value: stageDurationText(sleep.duration(for: .rem)))
                    LabeledContent("Awake", value: stageDurationText(sleep.duration(for: .awake)))
                    if sleep.duration(for: .asleepUnspecified) > 0 {
                        LabeledContent("未分类睡眠", value: durationText(sleep.duration(for: .asleepUnspecified)))
                    }
                } else {
                    Text("暂无数据").foregroundStyle(.secondary)
                }
            }

            Section {
                Button(viewModel.hasLoaded ? "重新读取" : "连接并读取") {
                    Task { await viewModel.authorizeAndLoad() }
                }
                .disabled(viewModel.state == .loading)
            }
        }
        .navigationTitle("HealthKit Probe")
    }

    @ViewBuilder
    private var statusSection: some View {
        switch viewModel.state {
        case .idle, .loaded:
            EmptyView()
        case .loading:
            Section {
                HStack { ProgressView(); Text("正在读取 HealthKit…") }
            }
        case .empty:
            Section { Text("四项数据均暂无数据") }
        case .error(let message):
            Section("错误") { Text(message).foregroundStyle(.red) }
        }
    }

    private func optionalText(_ value: String?) -> Text {
        Text(value ?? "暂无数据")
            .foregroundStyle(value == nil ? .secondary : .primary)
    }

    private func durationText(_ duration: TimeInterval) -> String {
        let minutes = Int(duration / 60)
        return "\(minutes / 60) 小时 \(minutes % 60) 分钟"
    }

    private func stageDurationText(_ duration: TimeInterval) -> String {
        duration > 0 ? durationText(duration) : "暂无数据"
    }
}

#Preview {
    NavigationStack { HealthKitProbeView() }
}
