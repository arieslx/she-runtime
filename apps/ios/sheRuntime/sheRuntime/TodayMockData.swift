//
//  TodayMockData.swift
//  sheRuntime
//
//  Today 页面的「文案 + 假数据」都放在这里。
//  产品(Ginger)改文字/数字只改这个文件，不用碰页面代码。
//  等艾瑞接通真实数据后，把这里的假数据替换成真数据即可。
//

import Foundation

// MARK: - 数据结构（一条时间线事件长什么样）

struct EnergyEvent: Identifiable {
    let id: UUID
    let time: String        // 时间，如 "10:40"
    let title: String       // 事件名，如 "团队会议"
    let note: String        // 说明，如 "高沟通负荷"
    let delta: Int          // 精力变化，正数回升/负数消耗，如 -8
    let energyBadge: TimelineEnergyBadge?

    init(
        id: UUID = UUID(),
        time: String,
        title: String,
        note: String,
        delta: Int,
        energyBadge: TimelineEnergyBadge? = nil
    ) {
        self.id = id
        self.time = time
        self.title = title
        self.note = note
        self.delta = delta
        self.energyBadge = energyBadge
    }
}

enum TimelineEnergyBadge: String, CaseIterable {
    case low
    case dipping
    case steady
    case good
    case full

    var copyKey: String { "today.energyBadge.\(rawValue)" }
}

// MARK: - Today 页面的全部文案和假数据

// 纯文案（标题、状态词、免责声明等）已迁到 Resources/copy_zh.json，用 C.t("today.*") 读。
// 这里只保留假数据：数值指标和时间线事件，等艾瑞接通真数据后替换。
enum TodayMock {

    // 精力主卡的数值
    static let energyScore = 68

    // 三个指标
    static let metricSleep = "7h 42m"
    static let metricHRV = "46 ms"
    static let metricRestingHR = "58 bpm"

    // 时间线事件（列表型假数据，非 JSON 文案）
    static let events: [EnergyEvent] = [
        EnergyEvent(time: "08:14", title: "起床",     note: "睡眠质量高于平时",   delta: 0),
        EnergyEvent(time: "09:32", title: "专注工作", note: "57 分钟 · 高度专注", delta: -5),
        EnergyEvent(time: "10:40", title: "团队会议", note: "沟通负荷较高",       delta: -8),
        EnergyEvent(time: "11:18", title: "语音记录", note: "“刚开完会，脑子有点转不动。”", delta: -6, energyBadge: .dipping),
        EnergyEvent(time: "11:32", title: "散步",     note: "6 分钟 · 轻度活动",  delta: 4)
    ]
}
