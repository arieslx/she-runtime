// HealthDataStore.swift — 工人A(数据层)
// 实现 SharedContracts.swift 里的 HealthDataStoring 协议。
// 本地持久化（SwiftData）+ HealthKit 锚点增量同步。
// 独立 ModelContainer，不依赖 sheRuntimeApp.swift 现有容器。
// 纯服务层：无任何用户可见文案。

import Foundation
import HealthKit
import SwiftData

// MARK: - SwiftData Entities

@Model
final class DailyHealthEntity {
    @Attribute(.unique) var date: Date
    var sleepHours: Double?
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

    init(date: Date) {
        self.date = date
    }
}

@Model
final class HourlyHealthEntity {
    @Attribute(.unique) var compositeKey: String
    var date: Date
    var hour: Int
    var heartRateMean: Double?
    var steps: Int?

    init(date: Date, hour: Int) {
        self.date = date
        self.hour = hour
        self.compositeKey = "\(date.timeIntervalSince1970)_\(hour)"
    }
}

@Model
final class SubjectiveNoteEntity {
    var date: Date
    var topicKey: String
    var text: String

    init(date: Date, topicKey: String, text: String) {
        self.date = date
        self.topicKey = topicKey
        self.text = text
    }
}

// MARK: - HealthDataStore

actor HealthDataStore: HealthDataStoring {
    static let shared = HealthDataStore()

    private let healthStore: HKHealthStore
    private let modelContainer: ModelContainer
    private let context: ModelContext
    private let calendar: Calendar
    private let anchorDefaultsPrefix = "HealthDataStore.anchor."

    private init() {
        self.healthStore = HKHealthStore()
        self.calendar = Calendar.current

        let schema = Schema([
            DailyHealthEntity.self,
            HourlyHealthEntity.self,
            SubjectiveNoteEntity.self,
        ])
        let container: ModelContainer
        do {
            let configuration = ModelConfiguration("HealthDataStore", schema: schema, isStoredInMemoryOnly: false)
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // Fallback: in-memory container so the app never crashes on storage failure.
            let memoryConfiguration = ModelConfiguration("HealthDataStoreMemory", schema: schema, isStoredInMemoryOnly: true)
            container = try! ModelContainer(for: schema, configurations: [memoryConfiguration])
        }
        self.modelContainer = container
        self.context = ModelContext(container)
        self.context.autosaveEnabled = false
    }

    // MARK: - HealthDataStoring Protocol

    func sync() async throws {
        try await syncQuantityTypes()
        try await syncSleepAnalysis()
        try await syncMenstrualFlow()
        try await syncHeartRateHourly()
    }

    func dailyRecords() async throws -> [DailyRecord] {
        let descriptor = FetchDescriptor<DailyHealthEntity>(sortBy: [SortDescriptor(\.date, order: .forward)])
        let entities = try context.fetch(descriptor)
        return entities.map { entity in
            DailyRecord(
                date: entity.date,
                sleepHours: entity.sleepHours,
                sleepOnsetMinutes: entity.sleepOnsetMinutes,
                hrv: entity.hrv,
                restingHeartRate: entity.restingHeartRate,
                wristTemp: entity.wristTemp,
                respiratoryRate: entity.respiratoryRate,
                steps: entity.steps,
                hasMenses: entity.hasMenses,
                headphoneHours: entity.headphoneHours,
                daylightMinutes: entity.daylightMinutes,
                mindfulMinutes: entity.mindfulMinutes
            )
        }
    }

    func hourlyRecords() async throws -> [HourlyRecord] {
        let descriptor = FetchDescriptor<HourlyHealthEntity>(sortBy: [
            SortDescriptor(\.date, order: .forward),
            SortDescriptor(\.hour, order: .forward)
        ])
        let entities = try context.fetch(descriptor)
        return entities.map { entity in
            HourlyRecord(
                date: entity.date,
                hour: entity.hour,
                heartRateMean: entity.heartRateMean,
                steps: entity.steps
            )
        }
    }

    func effectiveDayCount() async throws -> Int {
        let descriptor = FetchDescriptor<DailyHealthEntity>()
        let entities = try context.fetch(descriptor)
        return entities.filter { entity in
            entity.sleepHours != nil || entity.hrv != nil || entity.restingHeartRate != nil
        }.count
    }

    func recentAccrualRate() async throws -> Double {
        let now = Date()
        let startDate = calendar.date(byAdding: .day, value: -14, to: now)!

        let predicate = #Predicate<DailyHealthEntity> { entity in
            entity.date >= startDate
        }
        let descriptor = FetchDescriptor(predicate: predicate)
        let entities = try context.fetch(descriptor)

        let effectiveCount = entities.filter { entity in
            entity.sleepHours != nil || entity.hrv != nil || entity.restingHeartRate != nil
        }.count

        return Double(effectiveCount) / 14.0
    }

    /// Read-only compatibility source. New subjective events are written to TimelineRecord.
    var subjectiveNotes: [SubjectiveNote] {
        get async {
            let descriptor = FetchDescriptor<SubjectiveNoteEntity>(sortBy: [SortDescriptor(\.date, order: .forward)])
            guard let entities = try? context.fetch(descriptor) else { return [] }
            return entities.map { SubjectiveNote(date: $0.date, topicKey: $0.topicKey, text: $0.text) }
        }
    }

    // MARK: - Anchor Persistence

    private func loadAnchor(forKey key: String) -> HKQueryAnchor? {
        guard let data = UserDefaults.standard.data(forKey: anchorDefaultsPrefix + key) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    private func saveAnchor(_ anchor: HKQueryAnchor, forKey key: String) {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true) else { return }
        UserDefaults.standard.set(data, forKey: anchorDefaultsPrefix + key)
    }

    // MARK: - Query Helpers

    /// 锚点增量拉取：返回新增样本并持久化新锚点。锚点为 nil 时=历史全量。
    private func fetchNewSamples(of type: HKSampleType, anchorKey: String) async throws -> [HKSample] {
        let anchor = loadAnchor(forKey: anchorKey)
        let (samples, newAnchor): ([HKSample], HKQueryAnchor?) = try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: type,
                predicate: nil,
                anchor: anchor,
                limit: HKObjectQueryNoLimit
            ) { _, samples, _, newAnchor, error in
                if let error { continuation.resume(throwing: error); return }
                continuation.resume(returning: (samples ?? [], newAnchor))
            }
            healthStore.execute(query)
        }
        if let newAnchor { saveAnchor(newAnchor, forKey: anchorKey) }
        return samples
    }

    private func fetchSamples(of type: HKSampleType, start: Date, end: Date) async throws -> [HKSample] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        return try await withCheckedThrowingContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                continuation.resume(returning: samples ?? [])
            }
            healthStore.execute(query)
        }
    }

    /// 统计查询（均值或累计）。无数据返回 nil，不抛错。
    private func fetchStatistic(
        type: HKQuantityType,
        options: HKStatisticsOptions,
        unit: HKUnit,
        start: Date,
        end: Date
    ) async throws -> Double? {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: options
            ) { _, statistics, error in
                if let error {
                    let nsError = error as NSError
                    if nsError.domain == HKErrorDomain, nsError.code == HKError.errorNoData.rawValue {
                        continuation.resume(returning: nil)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                let quantity = options.contains(.cumulativeSum)
                    ? statistics?.sumQuantity()
                    : statistics?.averageQuantity()
                continuation.resume(returning: quantity?.doubleValue(for: unit))
            }
            healthStore.execute(query)
        }
    }

    // MARK: - Entity fetch-or-create

    private func dailyEntity(for day: Date) throws -> DailyHealthEntity {
        let predicate = #Predicate<DailyHealthEntity> { $0.date == day }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first { return existing }
        let entity = DailyHealthEntity(date: day)
        context.insert(entity)
        return entity
    }

    private func hourlyEntity(for day: Date, hour: Int) throws -> HourlyHealthEntity {
        let key = "\(day.timeIntervalSince1970)_\(hour)"
        let predicate = #Predicate<HourlyHealthEntity> { $0.compositeKey == key }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first { return existing }
        let entity = HourlyHealthEntity(date: day, hour: hour)
        context.insert(entity)
        return entity
    }

    private func affectedDays(from samples: [HKSample]) -> Set<Date> {
        Set(samples.map { calendar.startOfDay(for: $0.startDate) })
    }

    // MARK: - Sync: 每日 quantity 聚合

    /// 每日取值/累计类型。锚点查询做变更检测，受影响的天用统计查询整天重算（幂等）。
    private func syncQuantityTypes() async throws {
        struct DailyQuantityConfig {
            let identifier: HKQuantityTypeIdentifier
            let options: HKStatisticsOptions
            let unit: HKUnit
            let write: @Sendable (DailyHealthEntity, Double) -> Void
        }

        var configs: [DailyQuantityConfig] = [
            .init(identifier: .heartRateVariabilitySDNN, options: .discreteAverage,
                  unit: .secondUnit(with: .milli), write: { $0.hrv = $1 }),
            .init(identifier: .restingHeartRate, options: .discreteAverage,
                  unit: .count().unitDivided(by: .minute()), write: { $0.restingHeartRate = $1 }),
            .init(identifier: .appleSleepingWristTemperature, options: .discreteAverage,
                  unit: .degreeCelsius(), write: { $0.wristTemp = $1 }),
            .init(identifier: .respiratoryRate, options: .discreteAverage,
                  unit: .count().unitDivided(by: .minute()), write: { $0.respiratoryRate = $1 }),
            .init(identifier: .stepCount, options: .cumulativeSum,
                  unit: .count(), write: { $0.steps = Int($1) }),
        ]
        if #available(iOS 17.0, *) {
            configs.append(.init(identifier: .timeInDaylight, options: .cumulativeSum,
                                 unit: .minute(), write: { $0.daylightMinutes = $1 }))
        }

        for config in configs {
            guard let type = HKQuantityType.quantityType(forIdentifier: config.identifier) else { continue }
            let newSamples: [HKSample]
            do {
                newSamples = try await fetchNewSamples(of: type, anchorKey: config.identifier.rawValue)
            } catch {
                continue  // 单类型失败不阻断整体同步（如未授权）
            }
            guard !newSamples.isEmpty else { continue }
            for day in affectedDays(from: newSamples) {
                let dayEnd = calendar.date(byAdding: .day, value: 1, to: day)!
                if let value = try? await fetchStatistic(
                    type: type, options: config.options, unit: config.unit, start: day, end: dayEnd
                ) {
                    let entity = try dailyEntity(for: day)
                    config.write(entity, value)
                }
            }
            try? context.save()
        }

        // 耳机音量暴露：按样本时长累计小时（统计查询给不出时长）
        try await syncDurationQuantity(.headphoneAudioExposure, anchorKey: "headphoneDuration") { entity, hours in
            entity.headphoneHours = hours
        }
        // 正念：category 样本时长累计分钟
        try await syncMindfulMinutes()
    }

    private func syncDurationQuantity(
        _ identifier: HKQuantityTypeIdentifier,
        anchorKey: String,
        write: (DailyHealthEntity, Double) -> Void
    ) async throws {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return }
        let newSamples: [HKSample]
        do {
            newSamples = try await fetchNewSamples(of: type, anchorKey: anchorKey)
        } catch { return }
        guard !newSamples.isEmpty else { return }
        for day in affectedDays(from: newSamples) {
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: day)!
            guard let samples = try? await fetchSamples(of: type, start: day, end: dayEnd) else { continue }
            let seconds = samples.reduce(0.0) { total, sample in
                total + min(sample.endDate, dayEnd).timeIntervalSince(max(sample.startDate, day))
            }
            let entity = try dailyEntity(for: day)
            write(entity, seconds / 3600.0)
        }
        try? context.save()
    }

    private func syncMindfulMinutes() async throws {
        guard let type = HKCategoryType.categoryType(forIdentifier: .mindfulSession) else { return }
        let newSamples: [HKSample]
        do {
            newSamples = try await fetchNewSamples(of: type, anchorKey: "mindfulSession")
        } catch { return }
        guard !newSamples.isEmpty else { return }
        for day in affectedDays(from: newSamples) {
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: day)!
            guard let samples = try? await fetchSamples(of: type, start: day, end: dayEnd) else { continue }
            let seconds = samples.reduce(0.0) { total, sample in
                total + min(sample.endDate, dayEnd).timeIntervalSince(max(sample.startDate, day))
            }
            let entity = try dailyEntity(for: day)
            entity.mindfulMinutes = seconds / 60.0
        }
        try? context.save()
    }

    // MARK: - Sync: 睡眠分析（session 合并 + 归属日 + onset）

    /// 当晚睡眠归属第二天：查询窗口 = 前一天中午12:00 → 当天中午12:00。
    private func syncSleepAnalysis() async throws {
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return }
        let newSamples: [HKSample]
        do {
            newSamples = try await fetchNewSamples(of: type, anchorKey: "sleepAnalysis")
        } catch { return }  // 未授权等失败不阻断整体同步
        guard !newSamples.isEmpty else { return }

        let categorySamples = newSamples.compactMap { $0 as? HKCategorySample }
        for day in affectedSleepDays(from: categorySamples) {
            let window = sleepWindow(for: day)
            // 用完整窗口重查该归属日全部睡眠样本（幂等重算，不只用增量样本）
            guard let windowSamples = try? await fetchSamples(of: type, start: window.start, end: window.end) else { continue }
            let daySamples = (windowSamples.compactMap { $0 as? HKCategorySample })
                .filter { sleepStage(forValue: $0.value) != nil }
            guard let result = aggregateSleep(daySamples, window: window) else { continue }
            let entity = try dailyEntity(for: day)
            entity.sleepHours = result.sleepHours
            entity.sleepOnsetMinutes = Int(result.onset.timeIntervalSince(day) / 60.0)
        }
        try? context.save()
    }

    private func sleepWindow(for day: Date) -> (start: Date, end: Date) {
        let noon = calendar.date(byAdding: .hour, value: 12, to: day)!
        let previousNoon = calendar.date(byAdding: .day, value: -1, to: noon)!
        return (previousNoon, noon)
    }

    /// 样本可能横跨两个归属日窗口，两边都标记为受影响。
    private func affectedSleepDays(from samples: [HKCategorySample]) -> Set<Date> {
        var days = Set<Date>()
        for sample in samples {
            let endDay = calendar.startOfDay(for: sample.endDate)
            let nextDay = calendar.date(byAdding: .day, value: 1, to: endDay)!
            for candidate in [endDay, nextDay] {
                let window = sleepWindow(for: candidate)
                if sample.endDate > window.start && sample.startDate < window.end {
                    days.insert(candidate)
                }
            }
        }
        return days
    }

    private struct SleepAggregate {
        var sleepHours: Double
        var onset: Date
    }

    /// session 合并（90分钟gap）→ 取总睡眠最长的 primary session。
    /// sleepHours = asleep 阶段合并时长；onset = primary session 内首个 asleep 样本开始时刻。
    private func aggregateSleep(_ samples: [HKCategorySample], window: (start: Date, end: Date)) -> SleepAggregate? {
        guard !samples.isEmpty else { return nil }
        let gap: TimeInterval = 90 * 60

        let clipped = samples.compactMap { sample -> DateInterval? in
            let start = max(sample.startDate, window.start)
            let end = min(sample.endDate, window.end)
            return end > start ? DateInterval(start: start, end: end) : nil
        }
        let sessions = mergeIntervals(clipped, maximumGap: gap)

        var best: (session: DateInterval, sleepSeconds: TimeInterval, onset: Date)?
        for session in sessions {
            let sessionSamples = samples.filter { $0.endDate > session.start && $0.startDate < session.end }
            let asleepIntervals = sessionSamples.compactMap { sample -> DateInterval? in
                guard let stage = sleepStage(forValue: sample.value), stage.countsAsActualSleep else { return nil }
                let start = max(sample.startDate, session.start)
                let end = min(sample.endDate, session.end)
                return end > start ? DateInterval(start: start, end: end) : nil
            }
            guard let firstAsleep = asleepIntervals.min(by: { $0.start < $1.start }) else { continue }
            let sleepSeconds = mergeIntervals(asleepIntervals, maximumGap: 0).reduce(0.0) { $0 + $1.duration }
            guard sleepSeconds > 0 else { continue }
            if best == nil
                || sleepSeconds > best!.sleepSeconds
                || (sleepSeconds == best!.sleepSeconds && session.end > best!.session.end) {
                best = (session, sleepSeconds, firstAsleep.start)
            }
        }
        guard let best else { return nil }
        return SleepAggregate(sleepHours: best.sleepSeconds / 3600.0, onset: best.onset)
    }

    private func mergeIntervals(_ intervals: [DateInterval], maximumGap: TimeInterval) -> [DateInterval] {
        let sorted = intervals.sorted { $0.start < $1.start }
        guard let first = sorted.first else { return [] }
        var currentStart = first.start
        var currentEnd = first.end
        var result: [DateInterval] = []
        for interval in sorted.dropFirst() {
            if interval.start.timeIntervalSince(currentEnd) <= maximumGap {
                currentEnd = max(currentEnd, interval.end)
            } else {
                result.append(DateInterval(start: currentStart, end: currentEnd))
                currentStart = interval.start
                currentEnd = interval.end
            }
        }
        result.append(DateInterval(start: currentStart, end: currentEnd))
        return result
    }

    private enum SleepStage {
        case asleepUnspecified, core, deep, rem, awake, inBed

        var countsAsActualSleep: Bool {
            switch self {
            case .asleepUnspecified, .core, .deep, .rem: true
            case .awake, .inBed: false
            }
        }
    }

    private func sleepStage(forValue value: Int) -> SleepStage? {
        switch value {
        case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue: .asleepUnspecified
        case HKCategoryValueSleepAnalysis.asleepCore.rawValue: .core
        case HKCategoryValueSleepAnalysis.asleepDeep.rawValue: .deep
        case HKCategoryValueSleepAnalysis.asleepREM.rawValue: .rem
        case HKCategoryValueSleepAnalysis.awake.rawValue: .awake
        case HKCategoryValueSleepAnalysis.inBed.rawValue: .inBed
        default: nil
        }
    }

    // MARK: - Sync: 月经

    private func syncMenstrualFlow() async throws {
        guard let type = HKCategoryType.categoryType(forIdentifier: .menstrualFlow) else { return }
        let newSamples: [HKSample]
        do {
            newSamples = try await fetchNewSamples(of: type, anchorKey: "menstrualFlow")
        } catch { return }
        guard !newSamples.isEmpty else { return }

        // 样本可跨多天：把覆盖到的每个日历天都标 hasMenses
        var days = Set<Date>()
        for sample in newSamples {
            guard sample is HKCategorySample else { continue }
            var day = calendar.startOfDay(for: sample.startDate)
            let lastDay = calendar.startOfDay(for: sample.endDate)
            while day <= lastDay {
                days.insert(day)
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }
        for day in days {
            let entity = try dailyEntity(for: day)
            entity.hasMenses = true
        }
        try? context.save()
    }

    // MARK: - Sync: 心率按小时聚合（顺带该小时步数）

    private func syncHeartRateHourly() async throws {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate),
              let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return }
        let newSamples: [HKSample]
        do {
            newSamples = try await fetchNewSamples(of: hrType, anchorKey: "heartRateHourly")
        } catch { return }
        guard !newSamples.isEmpty else { return }

        // 受影响的 (日, 小时) 桶
        var buckets = Set<Date>()  // 小时起点
        for sample in newSamples {
            var components = calendar.dateComponents([.year, .month, .day, .hour], from: sample.startDate)
            components.minute = 0
            components.second = 0
            if let hourStart = calendar.date(from: components) {
                buckets.insert(hourStart)
            }
        }

        let bpmUnit = HKUnit.count().unitDivided(by: .minute())
        for hourStart in buckets.sorted() {
            guard let hourEnd = calendar.date(byAdding: .hour, value: 1, to: hourStart) else { continue }
            let day = calendar.startOfDay(for: hourStart)
            let hour = calendar.component(.hour, from: hourStart)

            let hrMean = try? await fetchStatistic(
                type: hrType, options: .discreteAverage, unit: bpmUnit,
                start: hourStart, end: hourEnd
            )
            let stepSum = try? await fetchStatistic(
                type: stepType, options: .cumulativeSum, unit: .count(),
                start: hourStart, end: hourEnd
            )

            let entity = try hourlyEntity(for: day, hour: hour)
            if let hrMean { entity.heartRateMean = hrMean }
            if let stepSum { entity.steps = Int(stepSum) }
        }
        try? context.save()
    }
}
