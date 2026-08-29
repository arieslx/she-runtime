// SharedContracts.swift — 三个工人共用的接口契约（总管定死，工人不许改此文件）
// 工人A(数据层) 实现 HealthDataStoring；工人B(引擎) 消费它、产出 EngineOutput；
// 工人C(引导页) 消费 EngineOutput.guidance。总管最后接线 InsightsView。
// 本文件由总管唯一维护。

import Foundation

// MARK: - 数据层契约（工人A实现）

/// 每日聚合记录。字段允许为 nil = 那天没有该数据。
struct DailyRecord: Sendable {
    var date: Date
    var sleepHours: Double?
    /// 入睡时刻，相对当天 00:00 的分钟数；前一晚 22:30 = -90，凌晨 2:00 = 120
    var sleepOnsetMinutes: Int?
    var hrv: Double?
    var restingHeartRate: Double?
    var wristTemp: Double?
    var respiratoryRate: Double?
    var steps: Int?
    var hasMenses: Bool = false
    var headphoneHours: Double?
    var daylightMinutes: Double?
    var mindfulMinutes: Double?
}

/// 小时聚合记录。
struct HourlyRecord: Sendable {
    var date: Date
    var hour: Int  // 0-23
    var heartRateMean: Double?
    var steps: Int?
}

/// 用户主观回答（16号文档：她的每句话都是数据）。
struct SubjectiveNote: Sendable, Identifiable, Equatable {
    var id: String
    var date: Date
    var topicKey: String   // 对应问题方向，如 "sleep_onset"
    var text: String
    var source: String
    var rawText: String
    var timezoneIdentifier: String?
    var extractionStatus: SubjectiveExtractionStatus
    var confirmationStatus: SubjectiveConfirmationStatus
    var revision: Int

    nonisolated init(
        date: Date,
        topicKey: String,
        text: String,
        id: String = UUID().uuidString,
        source: String = SubjectiveEventSource.legacy.rawValue,
        rawText: String? = nil,
        timezoneIdentifier: String? = nil,
        extractionStatus: SubjectiveExtractionStatus = .unknown,
        confirmationStatus: SubjectiveConfirmationStatus = .unknown,
        revision: Int = 1
    ) {
        self.id = id
        self.date = date
        self.topicKey = topicKey
        self.text = text
        self.source = source
        self.rawText = rawText ?? text
        self.timezoneIdentifier = timezoneIdentifier
        self.extractionStatus = extractionStatus
        self.confirmationStatus = confirmationStatus
        self.revision = revision
    }
}

protocol HealthDataStoring: Sendable {
    /// 增量同步：锚点查询拉新样本进本地库。首次调用做历史全量导入（后台）。
    func sync() async throws
    /// 全部每日聚合（升序）。引擎每次全量读。
    func dailyRecords() async throws -> [DailyRecord]
    /// 全部小时聚合（升序）。
    func hourlyRecords() async throws -> [HourlyRecord]
    /// 有效数据天数（至少一个字段非nil的天数）——置信度阶梯用。
    func effectiveDayCount() async throws -> Int
    /// 最近14天的数据积累速度（有效天/日历天）——估算"还要几天"用。
    func recentAccrualRate() async throws -> Double
    var subjectiveNotes: [SubjectiveNote] { get async }
}

// MARK: - 引擎输出契约（工人B产出，页面渲染）

/// 置信度阶梯（0829 Ginger 定：不是开关，是话说多满）
enum ConfidenceTier: Sendable {
    case guess       // 极少数据："我猜……是这样吗？"求证态
    case observing   // 初步倾向："还在观察的线索"苗头态
    case established // 数据充分："我的规律"笃定态
}

/// 一条算出来的规律/推测。文案=模板键+槽位值，页面用 C.t(键) 渲染后填槽。
struct ComputedInsight: Sendable, Identifiable {
    var id: String              // 如 "cyclePhase"
    var tier: ConfidenceTier
    var directionKey: String    // 模板选择键，如 "premenstrual_worse" / "no_pattern"
    var slots: [String: String] // 模板槽位值，如 ["cycleCount": "22"]
    var l3Numbers: [String: Double]  // 下钻层原始数字
    var priority: Int           // 排序（当下相关>杠杆>新鲜，13号文档三把尺）
    var askKey: String?         // tier==guess/observing 时的求反馈问题键
}

/// "再攒X天说得更准"的进度（按有效数据天+积累速度算，非日历天）。
struct AccrualProgress: Sendable {
    var recipeId: String
    var effectiveDays: Int
    var requiredDays: Int
    var estimatedCalendarDaysLeft: Int
}

enum SubjectiveAlignmentClaim: String, Sendable {
    /// The user's statement is saved, but there is no same-day objective data to compare.
    case factOnly = "fact_only"
    /// Subjective and objective records share a calendar-day window; no direction or cause is claimed.
    case cooccurrence
}

enum SubjectiveAlignmentConfidence: String, Sendable {
    case notEvaluated = "not_evaluated"
}

struct ObjectiveEvidenceFact: Sendable, Equatable, Identifiable {
    var id: String { metricKey }
    var metricKey: String
    var value: Double
    var unitKey: String
}

/// A deliberately restrained subjective-objective join. It is evidence for inspection,
/// not a pattern and never upgrades a single statement to causality.
struct SubjectiveObjectiveAlignment: Sendable, Equatable, Identifiable {
    var id: String
    var sourceEventID: String
    var source: String
    var userText: String
    var occurredAt: Date
    var timezoneIdentifier: String?
    var windowStart: Date
    var windowEnd: Date
    var claim: SubjectiveAlignmentClaim
    var confidence: SubjectiveAlignmentConfidence
    var analysisVersion: String
    var confirmationStatus: SubjectiveConfirmationStatus
    var extractionStatus: SubjectiveExtractionStatus
    var objectiveFacts: [ObjectiveEvidenceFact]
}

/// 引擎一次计算的完整输出。
struct EngineOutput: Sendable {
    var insights: [ComputedInsight]       // 各tier都在内，页面按tier分区
    var progress: [AccrualProgress]       // 未到笃定档的配方进度
    var hasAnyData: Bool                  // false = 走零数据引导壳
    var subjectiveAlignments: [SubjectiveObjectiveAlignment]

    init(
        insights: [ComputedInsight],
        progress: [AccrualProgress],
        hasAnyData: Bool,
        subjectiveAlignments: [SubjectiveObjectiveAlignment] = []
    ) {
        self.insights = insights
        self.progress = progress
        self.hasAnyData = hasAnyData
        self.subjectiveAlignments = subjectiveAlignments
    }
}

// MARK: - 引擎契约（工人B实现）

protocol EvidenceComputing: Sendable {
    func compute(daily: [DailyRecord], hourly: [HourlyRecord],
                 notes: [SubjectiveNote]) -> EngineOutput
}
