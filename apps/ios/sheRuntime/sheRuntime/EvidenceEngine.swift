// EvidenceEngine.swift — 规律引擎（工人B）
// 实现 SharedContracts.EvidenceComputing。纯计算：只 import Foundation，无 IO/UI/HealthKit。
// 算法逐行移植 tools/build_evidence.py（数值逻辑不改）。
// 架构红线：引擎是通用函数 f(用户数据)->该用户规律，只算方向和数字，
// 按算出的方向选文案模板键（见 EvidenceTemplateCatalog.swift），绝不写死任何具体结论。

import Foundation

// MARK: - 阈值总表（产品可改，全部集中在此）

enum Thresholds {
    // —— established 门槛（13号文档）——
    static let cycleEstablishedCycles = 3        // 周期相位：3个完整周期
    static let streakEstablishedDays = 30        // 对比堆：30有效天
    static let streakEstablishedGroupN = 10      // 对比堆：两组各≥10天
    static let gradientEstablishedDays = 60      // 剂量梯度：60有效天
    static let intradayEstablishedDays = 30      // 日内地形：30天
    static let sentinelEstablishedDays = 28      // 异常哨兵：28天基线
    static let weekdayEstablishedDays = 56       // 星期节律：8周

    // —— observing = established 门槛的这个比例以上且能算出方向 ——
    static let observingFraction = 1.0 / 3.0

    // —— 方向判定 ——
    static let hrvWorseRelativeGap = 0.05        // HRV 相对差 ≥5% 才算显著
    static let rhrWorseAbsoluteGap = 1.0         // RHR 绝对差 ≥1 bpm 才算显著
    static let wristTempGapC = 0.1               // 腕温差 ≥0.1°C 才算一个指标变差
    static let cycleWorseSignalCount = 2         // 周期相位：三指标至少2个变差
    static let weekdayLowGapHours = 0.4          // 星期节律：低谷日比整体中位低 >0.4h
    static let intradayGapBpm = 2.0              // 日内地形：上午/下午差 ≥2bpm 才算有地形
    static let gradientEnoughRatioGap = 0.15     // 梯度：before0 与 after3 睡够率差 ≥0.15

    // —— 算法常量（照抄 build_evidence.py，一般不动）——
    static let newCycleGapDays = 10              // 相邻经期日 >10 天 = 新周期
    static let mensesPhaseDays = 5               // 距周期起始 <5 天 = menses
    static let premenstrualDays = 7              // 距下次起始 ≤7 天 = premenstrual
    static let maxCycleLenDays = 60              // 前后起始跨度 >60 天不算相位
    static let validCycleMinDays = 15            // 计数周期：15..60 天
    static let onsetControlMin = -60             // 混杂核查：入睡 23:00 = -60
    static let onsetControlMax = 120             // 混杂核查：入睡 02:00 = 120
    static let enoughSleepHours = 7.0            // 睡够 = ≥7h
    static let shortSleepHours = 6.0             // 短睡 = 当天<6h 且前一天≥6h
    static let streakLength = 3                  // 连睡 3 天
    static let gradientAfter3Min = 180           // 入睡 >180 分 = after3
    static let seatedStepsMax = 50               // 静坐 = 小时步数 <50
    static let hourlyMinSamples = 30             // 每小时样本 ≥30 才计入曲线
    static let amHourRange = 9...12              // 上午
    static let pmHourRange = 13...20             // 下午
    static let sentinelPercentile = 0.95         // 腕温 P95
    static let premenstrualWindowDays = 7        // 当下相关：今天在经前7天窗口内

    // —— tier 判定辅助 ——
    static func tier(effective: Int, required: Int, hasDirection: Bool) -> ConfidenceTier? {
        if effective <= 0 { return nil }
        if effective >= required { return .established }
        if Double(effective) >= Double(required) * observingFraction && hasDirection {
            return .observing
        }
        return .guess
    }
}

// MARK: - 优先级（13号文档三把尺：当下相关 > 杠杆 > tier）

private enum Priority {
    // 数字越小越靠前
    static let nowWindow = 0      // 今天落在该规律窗口内
    static let leverage = 10      // 可行动杠杆（sleepStreak）
    static let established = 20
    static let observing = 30
    static let guess = 40

    static func base(for tier: ConfidenceTier) -> Int {
        switch tier {
        case .established: return established
        case .observing: return observing
        case .guess: return guess
        }
    }
}

// MARK: - 引擎

struct EvidenceEngine: EvidenceComputing {

    /// 最近14天有效天/日历天，由调用方（数据层 recentAccrualRate()）提供；
    /// compute(daily:hourly:notes:) 协议方法用此值估算"还差几天"。默认 1.0。
    var accrualRate: Double = 1.0

    init(accrualRate: Double = 1.0) {
        self.accrualRate = accrualRate
    }

    func compute(daily: [DailyRecord], hourly: [HourlyRecord],
                 notes: [SubjectiveNote]) -> EngineOutput {
        let hasAnyData = Self.hasAnyData(daily: daily, notes: notes) || !hourly.isEmpty
        guard hasAnyData else {
            return EngineOutput(insights: [], progress: [], hasAnyData: false)
        }

        let today = daily.map(\.date).max() ?? Date()
        var insights: [ComputedInsight] = []
        var progress: [AccrualProgress] = []

        let results: [(ComputedInsight?, AccrualProgress?)] = [
            computeCyclePhase(daily: daily, today: today),
            computeSleepStreak(daily: daily),
            computeOnsetGradient(daily: daily),
            computeIntraday(hourly: hourly),
            computeSentinel(daily: daily, today: today),
            computeWeekday(daily: daily),
        ]
        for (insight, prog) in results {
            if let insight { insights.append(insight) }
            if let prog { progress.append(prog) }
        }
        insights.sort { $0.priority < $1.priority }
        return EngineOutput(
            insights: insights,
            progress: progress,
            hasAnyData: true,
            subjectiveAlignments: computeSubjectiveAlignments(daily: daily, notes: notes)
        )
    }

    static func hasAnyData(daily: [DailyRecord], notes: [SubjectiveNote]) -> Bool {
        if !notes.isEmpty { return true }
        return daily.contains { isEffectiveDay($0) }
    }

    /// 有效天 = 至少一个数据字段非 nil（或有经期标记）
    static func isEffectiveDay(_ r: DailyRecord) -> Bool {
        r.sleepHours != nil || r.sleepOnsetMinutes != nil || r.hrv != nil
            || r.restingHeartRate != nil || r.wristTemp != nil
            || r.respiratoryRate != nil || r.steps != nil || r.hasMenses
            || r.headphoneHours != nil || r.daylightMinutes != nil
            || r.mindfulMinutes != nil
    }

    /// Joins a saved user statement to objective values from the same local calendar day.
    /// This is deliberately not a pattern recipe: one statement can only become a fact or
    /// a co-occurrence worth inspecting, never an inferred direction or cause.
    func computeSubjectiveAlignments(
        daily: [DailyRecord],
        notes: [SubjectiveNote]
    ) -> [SubjectiveObjectiveAlignment] {
        notes
            .sorted { $0.date > $1.date }
            .prefix(12)
            .map { note in
                var calendar = Calendar(identifier: .gregorian)
                if let identifier = note.timezoneIdentifier,
                   let timezone = TimeZone(identifier: identifier) {
                    calendar.timeZone = timezone
                }
                let windowStart = calendar.startOfDay(for: note.date)
                let windowEnd = calendar.date(byAdding: .day, value: 1, to: windowStart)
                    ?? note.date.addingTimeInterval(86_400)
                let record = daily.last { calendar.isDate($0.date, inSameDayAs: note.date) }
                let facts = record.map(Self.objectiveFacts) ?? []

                return SubjectiveObjectiveAlignment(
                    id: "subjective:\(note.id):v\(note.revision)",
                    sourceEventID: note.id,
                    source: note.source,
                    userText: note.text,
                    occurredAt: note.date,
                    timezoneIdentifier: note.timezoneIdentifier,
                    windowStart: windowStart,
                    windowEnd: windowEnd,
                    claim: facts.isEmpty ? .factOnly : .cooccurrence,
                    confidence: .notEvaluated,
                    analysisVersion: "subjective-objective-calendar-day-v1",
                    confirmationStatus: note.confirmationStatus,
                    extractionStatus: note.extractionStatus,
                    objectiveFacts: facts
                )
            }
    }

    nonisolated private static func objectiveFacts(_ record: DailyRecord) -> [ObjectiveEvidenceFact] {
        var facts: [ObjectiveEvidenceFact] = []

        func append(_ metricKey: String, _ value: Double?, _ unitKey: String) {
            guard let value else { return }
            facts.append(ObjectiveEvidenceFact(metricKey: metricKey, value: value, unitKey: unitKey))
        }

        append("sleep_hours", record.sleepHours, "hours")
        append("sleep_onset_minutes", record.sleepOnsetMinutes.map(Double.init), "minutes_after_midnight")
        append("hrv", record.hrv, "milliseconds")
        append("resting_heart_rate", record.restingHeartRate, "beats_per_minute")
        append("wrist_temperature", record.wristTemp, "celsius")
        append("respiratory_rate", record.respiratoryRate, "breaths_per_minute")
        append("steps", record.steps.map(Double.init), "steps")
        if record.hasMenses {
            append("menses", 1, "present")
        }
        append("headphone_hours", record.headphoneHours, "hours")
        append("daylight_minutes", record.daylightMinutes, "minutes")
        append("mindful_minutes", record.mindfulMinutes, "minutes")
        return facts
    }

    // MARK: 通用小工具

    func median(_ xs: [Double]) -> Double? {
        guard !xs.isEmpty else { return nil }
        let s = xs.sorted()
        let n = s.count
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
    }

    func makeProgress(recipeId: String, effectiveDays: Int, requiredDays: Int) -> AccrualProgress {
        let missing = max(requiredDays - effectiveDays, 0)
        let rate = max(accrualRate, 0.1)
        let daysLeft = missing == 0 ? 0 : Int(ceil(Double(missing) / rate))
        return AccrualProgress(recipeId: recipeId, effectiveDays: effectiveDays,
                               requiredDays: requiredDays,
                               estimatedCalendarDaysLeft: daysLeft)
    }

    static let cal = Calendar(identifier: .gregorian)

    /// 日历天序号（同一天同号），用于天数差 = Python 的 (dateB - dateA).days
    func dayNumber(_ date: Date) -> Int {
        Self.cal.ordinality(of: .day, in: .era, for: date) ?? 0
    }

    func daysBetween(_ a: Date, _ b: Date) -> Int {
        dayNumber(b) - dayNumber(a)
    }
}

// MARK: - 配方① 周期相位 cyclePhase

extension EvidenceEngine {

    func computeCyclePhase(daily: [DailyRecord], today: Date)
        -> (ComputedInsight?, AccrualProgress?) {
        // 经期起始提取：相邻经期日 >10 天 = 新周期（照抄原型）
        let mensesDays = daily.filter(\.hasMenses).map(\.date).sorted()
        var starts: [Date] = []
        var prev: Date? = nil
        for d in mensesDays {
            if prev == nil || daysBetween(prev!, d) > Thresholds.newCycleGapDays {
                starts.append(d)
            }
            prev = d
        }

        func phaseOf(_ d: Date) -> String? {
            let prevs = starts.filter { dayNumber($0) <= dayNumber(d) }
            let nxts = starts.filter { dayNumber($0) > dayNumber(d) }
            guard let p = prevs.last, let n = nxts.first,
                  daysBetween(p, n) <= Thresholds.maxCycleLenDays else { return nil }
            if daysBetween(p, d) < Thresholds.mensesPhaseDays { return "menses" }
            if daysBetween(d, n) <= Thresholds.premenstrualDays { return "premenstrual" }
            return "other"
        }

        // 三指标按 phase 收集
        var phHRV = [String: [Double]](), phRHR = [String: [Double]](), phTemp = [String: [Double]]()
        var phaseDayCount = 0
        for r in daily {
            guard let p = phaseOf(r.date) else { continue }
            phaseDayCount += 1
            if let v = r.hrv { phHRV[p, default: []].append(v) }
            if let v = r.restingHeartRate { phRHR[p, default: []].append(v) }
            if let v = r.wristTemp { phTemp[p, default: []].append(v) }
        }
        // 完整周期数：相邻起始间隔 15..60 天
        var nCycles = 0
        for (a, b) in zip(starts, starts.dropFirst()) {
            let gap = daysBetween(a, b)
            if gap >= Thresholds.validCycleMinDays && gap <= Thresholds.maxCycleLenDays {
                nCycles += 1
            }
        }

        // 混杂核查：仅取入睡 23:00-02:00（onset -60..120）的日子再比 HRV
        var preCtl: [Double] = [], othCtl: [Double] = []
        for r in daily {
            guard let o = r.sleepOnsetMinutes, let h = r.hrv,
                  let p = phaseOf(r.date) else { continue }
            if o >= Thresholds.onsetControlMin && o <= Thresholds.onsetControlMax {
                if p == "premenstrual" { preCtl.append(h) } else { othCtl.append(h) }
            }
        }

        let hasMensesData = !mensesDays.isEmpty
        // 有效数据量：以周期数为准（门槛单位是周期）；完全无经期数据→只出进度
        guard hasMensesData else {
            return (nil, makeProgress(recipeId: "cyclePhase", effectiveDays: 0,
                                      requiredDays: Thresholds.cycleEstablishedCycles))
        }

        let preHRV = median(phHRV["premenstrual"] ?? [])
        let othHRV = median(phHRV["other"] ?? [])
        let preRHR = median(phRHR["premenstrual"] ?? [])
        let othRHR = median(phRHR["other"] ?? [])
        let preTemp = median(phTemp["premenstrual"] ?? [])
        let othTemp = median(phTemp["other"] ?? [])

        // 方向判定：三指标至少 cycleWorseSignalCount 个变差 -> worse；反向 -> better
        var worse = 0, better = 0, signals = 0
        if let a = preHRV, let b = othHRV, b != 0 {
            signals += 1
            let rel = (b - a) / abs(b)   // HRV 低 = 差
            if rel >= Thresholds.hrvWorseRelativeGap { worse += 1 }
            else if rel <= -Thresholds.hrvWorseRelativeGap { better += 1 }
        }
        if let a = preRHR, let b = othRHR {
            signals += 1
            let gap = a - b              // RHR 高 = 差
            if gap >= Thresholds.rhrWorseAbsoluteGap { worse += 1 }
            else if gap <= -Thresholds.rhrWorseAbsoluteGap { better += 1 }
        }
        if let a = preTemp, let b = othTemp {
            signals += 1
            let gap = a - b              // 腕温高 = 差（相对基线偏离）
            if gap >= Thresholds.wristTempGapC { worse += 1 }
            else if gap <= -Thresholds.wristTempGapC { better += 1 }
        }

        var direction = "no_pattern"
        if signals > 0 {
            if worse >= Thresholds.cycleWorseSignalCount { direction = "premenstrual_worse" }
            else if better >= Thresholds.cycleWorseSignalCount { direction = "premenstrual_better" }
        }
        let hasDirection = direction != "no_pattern"

        // 有经期标记就算"有一点相关数据"：0 完整周期也给 guess
        let tier = Thresholds.tier(effective: nCycles,
                                   required: Thresholds.cycleEstablishedCycles,
                                   hasDirection: hasDirection) ?? .guess
        guard signals > 0 || tier == .guess
        else {
            // 有经期标记但连一个可比指标都没有：只出进度
            return (nil, makeProgress(recipeId: "cyclePhase", effectiveDays: nCycles,
                                      requiredDays: Thresholds.cycleEstablishedCycles))
        }

        var l3: [String: Double] = ["n_cycles": Double(nCycles),
                                    "phase_day_n": Double(phaseDayCount)]
        if let v = preHRV { l3["pre_hrv"] = v }
        if let v = othHRV { l3["other_hrv"] = v }
        if let v = median(phHRV["menses"] ?? []) { l3["menses_hrv"] = v }
        if let v = preRHR { l3["pre_rhr"] = v }
        if let v = othRHR { l3["other_rhr"] = v }
        if let v = median(phRHR["menses"] ?? []) { l3["menses_rhr"] = v }
        if let v = preTemp { l3["pre_temp"] = v }
        if let v = othTemp { l3["other_temp"] = v }
        if let v = median(preCtl) { l3["confound_pre_hrv"] = v }
        if let v = median(othCtl) { l3["confound_other_hrv"] = v }
        l3["confound_pre_n"] = Double(preCtl.count)
        l3["confound_other_n"] = Double(othCtl.count)

        var slots: [String: String] = ["cycleCount": "\(nCycles)"]
        if let a = preHRV, let b = othHRV, b != 0 {
            slots["hrvGapPercent"] = "\(Int((abs(b - a) / abs(b) * 100).rounded()))"
        }
        if let a = preRHR, let b = othRHR {
            slots["rhrGap"] = String(format: "%.1f", abs(a - b))
        }

        // guess 档：只产出求证式推测
        let directionKey: String
        let askKey: String?
        switch tier {
        case .guess:
            directionKey = "guess_" + direction
            askKey = "ask.cyclePhase.guess"
        case .observing:
            directionKey = direction
            askKey = "ask.cyclePhase.observing"
        case .established:
            directionKey = direction
            askKey = nil
        }

        // 当下相关：今天距下一次预计经期起始 ≤7 天（用中位周期长估下一次）
        var priority = Priority.base(for: tier)
        if hasDirection, let last = starts.last, nCycles >= 1 {
            let gaps = zip(starts, starts.dropFirst()).map { daysBetween($0, $1) }
                .filter { $0 >= Thresholds.validCycleMinDays && $0 <= Thresholds.maxCycleLenDays }
            if let m = median(gaps.map(Double.init)) {
                let nextStart = dayNumber(last) + Int(m.rounded())
                let toNext = nextStart - dayNumber(today)
                if toNext >= 0 && toNext <= Thresholds.premenstrualWindowDays {
                    priority = Priority.nowWindow
                }
            }
        }

        let insight = ComputedInsight(id: "cyclePhase", tier: tier,
                                      directionKey: directionKey, slots: slots,
                                      l3Numbers: l3, priority: priority, askKey: askKey)
        let prog: AccrualProgress? = tier == .established ? nil
            : makeProgress(recipeId: "cyclePhase", effectiveDays: nCycles,
                           requiredDays: Thresholds.cycleEstablishedCycles)
        return (insight, prog)
    }
}

// MARK: - 配方② 对比堆 sleepStreak

extension EvidenceEngine {

    func computeSleepStreak(daily: [DailyRecord]) -> (ComputedInsight?, AccrualProgress?) {
        // 按日历天索引 sleepHours，支持 sleeps(d, 3) 回看
        var sleepByDay = [Int: Double]()
        for r in daily where r.sleepHours != nil {
            sleepByDay[dayNumber(r.date)] = r.sleepHours
        }

        var rested: [Double] = [], short1: [Double] = []
        var effectiveDays = 0
        for r in daily {
            guard let rhr = r.restingHeartRate else { continue }
            let d = dayNumber(r.date)
            // s3 = [当天, 前1天, 前2天]，任一缺失则跳过（照抄原型 sleeps）
            guard let s0 = sleepByDay[d], let s1 = sleepByDay[d - 1],
                  let s2 = sleepByDay[d - 2] else { continue }
            effectiveDays += 1
            let s3 = [s0, s1, s2]
            if s3.allSatisfy({ $0 >= Thresholds.enoughSleepHours }) { rested.append(rhr) }
            if s0 < Thresholds.shortSleepHours && s1 >= Thresholds.shortSleepHours {
                short1.append(rhr)
            }
        }

        // 睡眠或RHR全缺 = 该配方数据为0：只出进度
        let hasRaw = daily.contains { $0.sleepHours != nil }
            && daily.contains { $0.restingHeartRate != nil }
        guard hasRaw else {
            return (nil, makeProgress(recipeId: "sleepStreak", effectiveDays: 0,
                                      requiredDays: Thresholds.streakEstablishedDays))
        }

        let restedM = median(rested)
        let shortM = median(short1)

        var direction = "no_pattern"
        if let a = restedM, let b = shortM {
            let gap = b - a   // 短睡日 RHR 高 = 睡够有用
            if gap >= Thresholds.rhrWorseAbsoluteGap { direction = "streak_helps" }
            else if gap <= -Thresholds.rhrWorseAbsoluteGap { direction = "streak_inverse" }
        }
        let hasDirection = direction != "no_pattern"

        // established 额外要求两组各 ≥10
        let groupsOK = rested.count >= Thresholds.streakEstablishedGroupN
            && short1.count >= Thresholds.streakEstablishedGroupN
        // 有睡眠+RHR 原始数据但凑不出连续3天窗口：也算"有一点相关数据"→ guess
        var tier = Thresholds.tier(effective: effectiveDays,
                                   required: Thresholds.streakEstablishedDays,
                                   hasDirection: hasDirection) ?? .guess
        if tier == .established && !groupsOK { tier = hasDirection ? .observing : .guess }

        var l3: [String: Double] = ["effective_days": Double(effectiveDays),
                                    "rested_n": Double(rested.count),
                                    "short_n": Double(short1.count)]
        if let v = restedM { l3["rested_rhr"] = v }
        if let v = shortM { l3["short_rhr"] = v }

        var slots: [String: String] = ["restedCount": "\(rested.count)"]
        if let a = restedM, let b = shortM {
            slots["rhrGap"] = String(format: "%.0f", abs(b - a))
        }

        let directionKey: String
        let askKey: String?
        switch tier {
        case .guess:
            directionKey = "guess_" + direction
            askKey = "ask.sleepStreak.guess"
        case .observing:
            directionKey = direction
            askKey = "ask.sleepStreak.observing"
        case .established:
            directionKey = direction
            askKey = nil
        }

        // 杠杆律：可行动配方，established 且有方向时优先级提到 leverage 档
        var priority = Priority.base(for: tier)
        if tier == .established && hasDirection { priority = Priority.leverage }

        let insight = ComputedInsight(id: "sleepStreak", tier: tier,
                                      directionKey: directionKey, slots: slots,
                                      l3Numbers: l3, priority: priority, askKey: askKey)
        let prog: AccrualProgress? = tier == .established ? nil
            : makeProgress(recipeId: "sleepStreak", effectiveDays: effectiveDays,
                           requiredDays: Thresholds.streakEstablishedDays)
        return (insight, prog)
    }
}

// MARK: - 配方③ 剂量梯度 onsetGradient

extension EvidenceEngine {

    func computeOnsetGradient(daily: [DailyRecord]) -> (ComputedInsight?, AccrualProgress?) {
        var grad: [String: [Double]] = ["before0": [], "h1to3": [], "after3": []]
        var enough: [String: [Int]] = ["before0": [], "after3": []]
        var effectiveDays = 0
        for r in daily {
            guard let o = r.sleepOnsetMinutes else { continue }
            effectiveDays += 1
            let g = o <= 0 ? "before0" : (o > Thresholds.gradientAfter3Min ? "after3" : "h1to3")
            if let h = r.hrv { grad[g]?.append(h) }
            if let s = r.sleepHours, enough[g] != nil {
                enough[g]?.append(s >= Thresholds.enoughSleepHours ? 1 : 0)
            }
        }
        guard effectiveDays > 0 else {
            return (nil, makeProgress(recipeId: "onsetGradient", effectiveDays: 0,
                                      requiredDays: Thresholds.gradientEstablishedDays))
        }

        let hrvB0 = median(grad["before0"] ?? [])
        let hrv13 = median(grad["h1to3"] ?? [])
        let hrvA3 = median(grad["after3"] ?? [])
        func ratio(_ k: String) -> Double? {
            guard let v = enough[k], !v.isEmpty else { return nil }
            return Double(v.reduce(0, +)) / Double(v.count)
        }
        let ratioB0 = ratio("before0")
        let ratioA3 = ratio("after3")

        // 方向：晚睡是否有代价——HRV 梯度与睡够率差，取显著者
        var worseVotes = 0, betterVotes = 0
        if let a = hrvB0, let c = hrvA3, a != 0 {
            let rel = (a - c) / abs(a)   // after3 HRV 更低 = 晚睡代价
            if rel >= Thresholds.hrvWorseRelativeGap { worseVotes += 1 }
            else if rel <= -Thresholds.hrvWorseRelativeGap { betterVotes += 1 }
        }
        if let a = ratioB0, let c = ratioA3 {
            if a - c >= Thresholds.gradientEnoughRatioGap { worseVotes += 1 }
            else if c - a >= Thresholds.gradientEnoughRatioGap { betterVotes += 1 }
        }
        var direction = "no_pattern"
        if worseVotes > 0 && betterVotes == 0 { direction = "late_costs" }
        else if betterVotes > 0 && worseVotes == 0 { direction = "late_no_cost" }
        let hasDirection = direction != "no_pattern"

        guard let tier = Thresholds.tier(effective: effectiveDays,
                                         required: Thresholds.gradientEstablishedDays,
                                         hasDirection: hasDirection)
        else { return (nil, nil) }

        var l3: [String: Double] = ["effective_days": Double(effectiveDays),
                                    "n_before0": Double(grad["before0"]?.count ?? 0),
                                    "n_h1to3": Double(grad["h1to3"]?.count ?? 0),
                                    "n_after3": Double(grad["after3"]?.count ?? 0)]
        if let v = hrvB0 { l3["hrv_before0"] = v }
        if let v = hrv13 { l3["hrv_h1to3"] = v }
        if let v = hrvA3 { l3["hrv_after3"] = v }
        if let v = ratioB0 { l3["enough_ratio_before0"] = v }
        if let v = ratioA3 { l3["enough_ratio_after3"] = v }

        var slots: [String: String] = ["days": "\(effectiveDays)"]
        if let v = ratioB0 { slots["enoughPercentEarly"] = "\(Int((v * 100).rounded()))" }
        if let v = ratioA3 { slots["enoughPercentLate"] = "\(Int((v * 100).rounded()))" }

        let directionKey: String
        let askKey: String?
        switch tier {
        case .guess:
            directionKey = "guess_" + direction
            askKey = "ask.onsetGradient.guess"
        case .observing:
            directionKey = direction
            askKey = "ask.onsetGradient.observing"
        case .established:
            directionKey = direction
            askKey = nil
        }

        let insight = ComputedInsight(id: "onsetGradient", tier: tier,
                                      directionKey: directionKey, slots: slots,
                                      l3Numbers: l3, priority: Priority.base(for: tier),
                                      askKey: askKey)
        let prog: AccrualProgress? = tier == .established ? nil
            : makeProgress(recipeId: "onsetGradient", effectiveDays: effectiveDays,
                           requiredDays: Thresholds.gradientEstablishedDays)
        return (insight, prog)
    }
}

// MARK: - 配方④ 日内地形 intraday

extension EvidenceEngine {

    func computeIntraday(hourly: [HourlyRecord]) -> (ComputedInsight?, AccrualProgress?) {
        // 静坐时段（步数<50）心率按小时收集（照抄原型：steps 缺失按 0 计）
        var byHour = [Int: [Double]]()
        var effectiveDaySet = Set<Int>()
        for r in hourly {
            guard let hr = r.heartRateMean else { continue }
            effectiveDaySet.insert(dayNumber(r.date))
            if Double(r.steps ?? 0) < Double(Thresholds.seatedStepsMax) {
                byHour[r.hour, default: []].append(hr)
            }
        }
        let effectiveDays = effectiveDaySet.count
        guard effectiveDays > 0 else {
            return (nil, makeProgress(recipeId: "intraday", effectiveDays: 0,
                                      requiredDays: Thresholds.intradayEstablishedDays))
        }

        // 每小时样本 ≥30 才计入曲线
        var curve = [Int: Double]()
        for (h, v) in byHour where v.count >= Thresholds.hourlyMinSamples {
            if let m = median(v) { curve[h] = m }
        }
        let am = curve.filter { Thresholds.amHourRange.contains($0.key) }.map(\.value)
        let pm = curve.filter { Thresholds.pmHourRange.contains($0.key) }.map(\.value)
        let amM = median(am)
        let pmM = median(pm)

        var direction = "no_pattern"
        if let a = amM, let p = pmM {
            let gap = p - a
            if gap >= Thresholds.intradayGapBpm { direction = "am_calmer" }
            else if gap <= -Thresholds.intradayGapBpm { direction = "pm_calmer" }
        }
        let hasDirection = direction != "no_pattern"

        guard let tier = Thresholds.tier(effective: effectiveDays,
                                         required: Thresholds.intradayEstablishedDays,
                                         hasDirection: hasDirection)
        else { return (nil, nil) }

        var l3: [String: Double] = ["effective_days": Double(effectiveDays),
                                    "curve_hours_n": Double(curve.count)]
        for (h, v) in curve { l3["hr_h\(h)"] = v }
        if let v = amM { l3["am_median"] = v }
        if let v = pmM { l3["pm_median"] = v }

        var slots: [String: String] = [:]
        if let a = amM, let p = pmM {
            slots["hrGap"] = String(format: "%.0f", abs(p - a))
        }

        let directionKey: String
        let askKey: String?
        switch tier {
        case .guess:
            directionKey = "guess_" + direction
            askKey = "ask.intraday.guess"
        case .observing:
            directionKey = direction
            askKey = "ask.intraday.observing"
        case .established:
            directionKey = direction
            askKey = nil
        }

        let insight = ComputedInsight(id: "intraday", tier: tier,
                                      directionKey: directionKey, slots: slots,
                                      l3Numbers: l3, priority: Priority.base(for: tier),
                                      askKey: askKey)
        let prog: AccrualProgress? = tier == .established ? nil
            : makeProgress(recipeId: "intraday", effectiveDays: effectiveDays,
                           requiredDays: Thresholds.intradayEstablishedDays)
        return (insight, prog)
    }
}

// MARK: - 配方⑤ 异常哨兵 sentinel

extension EvidenceEngine {

    func computeSentinel(daily: [DailyRecord], today: Date) -> (ComputedInsight?, AccrualProgress?) {
        let tempsWithDate = daily.compactMap { r -> (Date, Double)? in
            guard let t = r.wristTemp else { return nil }
            return (r.date, t)
        }
        let effectiveDays = tempsWithDate.count
        guard effectiveDays > 0 else {
            return (nil, makeProgress(recipeId: "sentinel", effectiveDays: 0,
                                      requiredDays: Thresholds.sentinelEstablishedDays))
        }

        // P95 阈值（照抄原型：sorted[int(n*0.95)]）
        let temps = tempsWithDate.map(\.1).sorted()
        let idx = min(Int(Double(temps.count) * Thresholds.sentinelPercentile), temps.count - 1)
        let t95 = temps[idx]
        let hotDays = tempsWithDate.filter { $0.1 >= t95 }
        let todayHot = hotDays.contains { dayNumber($0.0) == dayNumber(today) }

        // 哨兵：基线是否建立。方向 = 基线就绪与否，非好坏对比
        let direction = "baseline_ready"
        guard let tier = Thresholds.tier(effective: effectiveDays,
                                         required: Thresholds.sentinelEstablishedDays,
                                         hasDirection: true)
        else { return (nil, nil) }

        let l3: [String: Double] = ["effective_days": Double(effectiveDays),
                                    "hot_threshold": t95,
                                    "hot_days_n": Double(hotDays.count),
                                    "today_hot": todayHot ? 1 : 0]
        let slots: [String: String] = ["hotDaysCount": "\(hotDays.count)",
                                       "baselineDays": "\(effectiveDays)"]

        let directionKey: String
        let askKey: String?
        switch tier {
        case .guess:
            // 基线累计中，不提"异常"二字（13号文档）——键区分开
            directionKey = "guess_baseline_building"
            askKey = "ask.sentinel.guess"
        case .observing:
            directionKey = "baseline_building"
            askKey = "ask.sentinel.observing"
        case .established:
            directionKey = direction
            askKey = nil
        }

        // 当下相关：今天就是超阈日
        var priority = Priority.base(for: tier)
        if tier == .established && todayHot { priority = Priority.nowWindow }

        let insight = ComputedInsight(id: "sentinel", tier: tier,
                                      directionKey: directionKey, slots: slots,
                                      l3Numbers: l3, priority: priority, askKey: askKey)
        let prog: AccrualProgress? = tier == .established ? nil
            : makeProgress(recipeId: "sentinel", effectiveDays: effectiveDays,
                           requiredDays: Thresholds.sentinelEstablishedDays)
        return (insight, prog)
    }
}

// MARK: - 附加配方 星期节律 weekday

extension EvidenceEngine {

    func computeWeekday(daily: [DailyRecord]) -> (ComputedInsight?, AccrualProgress?) {
        var byWeekday = [Int: [Double]]()   // 0=周一 … 6=周日（对齐 Python weekday()）
        var all: [Double] = []
        for r in daily {
            guard let s = r.sleepHours else { continue }
            let wd = (Self.cal.component(.weekday, from: r.date) + 5) % 7
            byWeekday[wd, default: []].append(s)
            all.append(s)
        }
        let effectiveDays = all.count
        guard effectiveDays > 0 else {
            return (nil, makeProgress(recipeId: "weekday", effectiveDays: 0,
                                      requiredDays: Thresholds.weekdayEstablishedDays))
        }

        var medians = [Int: Double]()
        for (wd, v) in byWeekday {
            if let m = median(v) { medians[wd] = m }
        }
        let overallM = median(all)

        // 显著低谷日：最低那天比整体中位低 >0.4h
        var direction = "no_pattern"
        var lowDay: Int? = nil
        if let overall = overallM, medians.count == 7,
           let lowest = medians.min(by: { $0.value < $1.value }) {
            if overall - lowest.value > Thresholds.weekdayLowGapHours {
                direction = "weekday_low"
                lowDay = lowest.key
            }
        }
        let hasDirection = direction != "no_pattern"

        guard let tier = Thresholds.tier(effective: effectiveDays,
                                         required: Thresholds.weekdayEstablishedDays,
                                         hasDirection: hasDirection)
        else { return (nil, nil) }

        var l3: [String: Double] = ["effective_days": Double(effectiveDays)]
        if let v = overallM { l3["overall_median"] = v }
        for (wd, m) in medians { l3["sleep_wd\(wd)"] = m }
        if let d = lowDay { l3["low_weekday"] = Double(d) }

        var slots: [String: String] = [:]
        if let d = lowDay {
            slots["lowWeekdayIndex"] = "\(d)"   // 0=周一…6=周日，星期名由文案层映射
            if let overall = overallM, let m = medians[d] {
                slots["sleepGapHours"] = String(format: "%.1f", overall - m)
            }
        }

        let directionKey: String
        let askKey: String?
        switch tier {
        case .guess:
            directionKey = "guess_" + direction
            askKey = "ask.weekday.guess"
        case .observing:
            directionKey = direction
            askKey = "ask.weekday.observing"
        case .established:
            directionKey = direction
            askKey = nil
        }

        let insight = ComputedInsight(id: "weekday", tier: tier,
                                      directionKey: directionKey, slots: slots,
                                      l3Numbers: l3, priority: Priority.base(for: tier),
                                      askKey: askKey)
        let prog: AccrualProgress? = tier == .established ? nil
            : makeProgress(recipeId: "weekday", effectiveDays: effectiveDays,
                           requiredDays: Thresholds.weekdayEstablishedDays)
        return (insight, prog)
    }
}
