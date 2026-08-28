// EvidenceTemplateCatalog.swift — 引擎模板键目录（工人B）
// 纯目录：列出引擎全部 directionKey / askKey 与 copy JSON 模板键的映射，及各键所需槽位。
// 不含任何用户可见文案——文案由总管写进 copy_zh.json。
// 模板键规则：insights.engine.<recipeId>.<directionKey>.l1（L2 同理换后缀）
// 求反馈问题键：ask.<recipeId>.<tier>

import Foundation

enum EvidenceTemplateCatalog {

    /// 一个方向键条目：copy JSON 里的模板键 + 渲染需要的槽位名
    struct Entry: Sendable {
        let recipeId: String
        let directionKey: String
        let copyKeyL1: String      // 第一层人话模板键
        let copyKeyL2: String      // 第二层展开模板键
        let slotNames: [String]    // 模板槽位名（引擎在 ComputedInsight.slots 提供）
    }

    static func copyKey(recipeId: String, directionKey: String, layer: String) -> String {
        "insights.engine.\(recipeId).\(directionKey).\(layer)"
    }

    private static func entry(_ recipe: String, _ direction: String, _ slots: [String]) -> Entry {
        Entry(recipeId: recipe, directionKey: direction,
              copyKeyL1: copyKey(recipeId: recipe, directionKey: direction, layer: "l1"),
              copyKeyL2: copyKey(recipeId: recipe, directionKey: direction, layer: "l2"),
              slotNames: slots)
    }

    /// 引擎会产出的全部 directionKey（含 guess_ 前缀的求证态变体）
    static let entries: [Entry] = [
        // ① 周期相位 cyclePhase — 槽位: cycleCount / hrvGapPercent / rhrGap
        entry("cyclePhase", "premenstrual_worse", ["cycleCount", "hrvGapPercent", "rhrGap"]),
        entry("cyclePhase", "premenstrual_better", ["cycleCount", "hrvGapPercent", "rhrGap"]),
        entry("cyclePhase", "no_pattern", ["cycleCount"]),
        entry("cyclePhase", "guess_premenstrual_worse", ["cycleCount"]),
        entry("cyclePhase", "guess_premenstrual_better", ["cycleCount"]),
        entry("cyclePhase", "guess_no_pattern", ["cycleCount"]),

        // ② 对比堆 sleepStreak — 槽位: restedCount / rhrGap
        entry("sleepStreak", "streak_helps", ["restedCount", "rhrGap"]),
        entry("sleepStreak", "streak_inverse", ["restedCount", "rhrGap"]),
        entry("sleepStreak", "no_pattern", ["restedCount"]),
        entry("sleepStreak", "guess_streak_helps", ["restedCount"]),
        entry("sleepStreak", "guess_streak_inverse", ["restedCount"]),
        entry("sleepStreak", "guess_no_pattern", ["restedCount"]),

        // ③ 剂量梯度 onsetGradient — 槽位: days / enoughPercentEarly / enoughPercentLate
        entry("onsetGradient", "late_costs", ["days", "enoughPercentEarly", "enoughPercentLate"]),
        entry("onsetGradient", "late_no_cost", ["days", "enoughPercentEarly", "enoughPercentLate"]),
        entry("onsetGradient", "no_pattern", ["days"]),
        entry("onsetGradient", "guess_late_costs", ["days"]),
        entry("onsetGradient", "guess_late_no_cost", ["days"]),
        entry("onsetGradient", "guess_no_pattern", ["days"]),

        // ④ 日内地形 intraday — 槽位: hrGap
        entry("intraday", "am_calmer", ["hrGap"]),
        entry("intraday", "pm_calmer", ["hrGap"]),
        entry("intraday", "no_pattern", []),
        entry("intraday", "guess_am_calmer", ["hrGap"]),
        entry("intraday", "guess_pm_calmer", ["hrGap"]),
        entry("intraday", "guess_no_pattern", []),

        // ⑤ 异常哨兵 sentinel — 槽位: hotDaysCount / baselineDays
        entry("sentinel", "baseline_ready", ["hotDaysCount", "baselineDays"]),
        entry("sentinel", "baseline_building", ["baselineDays"]),
        entry("sentinel", "guess_baseline_building", ["baselineDays"]),

        // 附加 星期节律 weekday — 槽位: lowWeekdayIndex(0=周一…6=周日) / sleepGapHours
        entry("weekday", "weekday_low", ["lowWeekdayIndex", "sleepGapHours"]),
        entry("weekday", "no_pattern", []),
        entry("weekday", "guess_weekday_low", ["lowWeekdayIndex", "sleepGapHours"]),
        entry("weekday", "guess_no_pattern", []),
    ]

    /// 求反馈问题键（tier==guess/observing 时 ComputedInsight.askKey 的取值全集）
    static let askKeys: [String] = [
        "ask.cyclePhase.guess", "ask.cyclePhase.observing",
        "ask.sleepStreak.guess", "ask.sleepStreak.observing",
        "ask.onsetGradient.guess", "ask.onsetGradient.observing",
        "ask.intraday.guess", "ask.intraday.observing",
        "ask.sentinel.guess", "ask.sentinel.observing",
        "ask.weekday.guess", "ask.weekday.observing",
    ]

    /// 进度文案模板键（AccrualProgress 渲染用；槽位: effectiveDays / requiredDays / daysLeft）
    static func progressCopyKey(recipeId: String) -> String {
        "insights.engine.\(recipeId).progress"
    }
}
