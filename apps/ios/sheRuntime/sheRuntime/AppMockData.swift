//
//  AppMockData.swift
//  sheRuntime
//
//  地图 / 洞察 / 问问 / 我的 四个页面的「文案 + 假数据」。
//  产品(Ginger)改文字只改这个文件。等真数据接通后替换。
//

import Foundation

// MARK: - 地图页

struct EnergyWindow: Identifiable {
    let id = UUID()
    let label: String   // "最佳专注时段"
    let range: String   // "09:20–11:10"
    let note: String
}

// 说明：各页的纯文案（标题、副标题、图例词、免责声明等）已迁到
// Resources/copy_zh.json，页面用 C.t("map.*") / C.t("insights.*") 等读取。
// 这里只保留「列表型/结构化假数据」和 JSON 未覆盖的数值，等真数据接通后替换。

enum MapMock {
    static let rangeText = "08:00 — 20:00"
    static let hourLabels = ["08", "10", "12", "14", "16", "18", "20"]
    static let windows: [EnergyWindow] = [
        EnergyWindow(label: "最佳专注时段", range: "09:20–11:10", note: "精力下降最慢，同时深度工作记录最多。"),
        EnergyWindow(label: "低精力时段",   range: "15:10–17:20", note: "连续沟通后，主观疲劳出现频率最高。")
    ]
    // 曲线上的采样点（0~1，0 是顶部高精力，1 是底部低精力），画图用
    static let curve: [Double] = [0.28, 0.22, 0.20, 0.32, 0.48, 0.58, 0.44, 0.50]
}

// MARK: - 洞察页

struct Insight: Identifiable {
    let id = UUID()
    let type: String        // "消耗项" / "恢复项" / "新线索"
    let count: String       // "出现 8 次" / "刚出现"
    let title: String
    let body: String
    let impact: String?     // "-21%" 可空
    let confidence: String? // "可信度 · 较高" 可空
}

enum InsightMock {
    static let insights: [Insight] = [
        Insight(type: "消耗项", count: "出现 8 次",
                title: "超过 90 分钟的会议",
                body: "过去两周里，超过 90 分钟的连续会议之后，你通常会在 2 小时内记录明显的脑力疲劳。",
                impact: "−21%", confidence: "可信度 · 较高"),
        Insight(type: "恢复项", count: "出现 11 次",
                title: "独自散步",
                body: "15–30 分钟的独处步行，是你最近最稳定的恢复行为之一，尤其发生在高沟通负荷之后。",
                impact: "+16%", confidence: "可信度 · 较高"),
        Insight(type: "新线索", count: "刚出现",
                title: "社交精力要看场合",
                body: "和朋友见面更常对应精力恢复；工作社交超过 90 分钟以后，精力下降更明显。",
                impact: nil, confidence: nil)
    ]
}

// MARK: - 问问页

enum AskMock {
    // 建议问题和示例回答是「列表/长文假数据」，留在这里；标题类文案走 JSON。
    static let suggestions = [
        "为什么我今天下午精力掉得这么快？",
        "我什么时候最适合做需要专注的工作？",
        "最近什么事情最消耗我？"
    ]
    static let sampleAnswer = "今天的身体恢复指标接近你的个人水平，下午精力下降主要发生在连续沟通之后。13:40–17:10 之间出现 4 次高用脑事件，其中 3 次是会议；过去四周，相似情况下你的主观精力通常下降 18–25%。\n\n共同出现不代表已经确认因果。"
}

// MARK: - 我的页

struct SettingRow: Identifiable {
    let id = UUID()
    let title: String
    let note: String
    let value: String
    let connected: Bool
}

enum ProfileMock {
    // 用户名和数值属于假数据；baselineSmall/baselineBody/coverageLabel 等纯文案走 JSON。
    static let name = "Nan"
    static let subtitle = "个人精力观察者 · 46 天"
    static let baselineTitle = "数据完整度 87%"
    static let coverage = 0.87

    static let dataSources: [SettingRow] = [
        SettingRow(title: "苹果健康", note: "睡眠、HRV、静息心率、活动量、运动", value: "已连接", connected: true),
        SettingRow(title: "语音记录", note: "生活事件、主观精力和上下文", value: "使用中", connected: true),
        SettingRow(title: "基线周期", note: "用于判断「今天和你平时相比如何」", value: "28 天", connected: false)
    ]
    static let privacyRows: [SettingRow] = [
        SettingRow(title: "健康权限", note: "管理当前允许读取的健康数据类型", value: "管理 ›", connected: false),
        SettingRow(title: "语音记录", note: "查看、修改或删除你的主动记录", value: "46 条 ›", connected: false),
        SettingRow(title: "导出我的数据", note: "导出结构化事件和个人趋势", value: "导出 ›", connected: false)
    ]
}
