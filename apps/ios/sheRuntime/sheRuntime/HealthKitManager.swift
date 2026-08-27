import Foundation
import HealthKit
import OSLog

final class HealthKitManager {
    enum ManagerError: LocalizedError {
        case unavailable
        case missingDataType(String)

        var errorDescription: String? {
            switch self {
            case .unavailable: "当前设备不支持 Apple Health"
            case .missingDataType(let name): "无法创建 HealthKit 数据类型：\(name)"
            }
        }
    }

    private struct Interval {
        var start: Date
        var end: Date
        var duration: TimeInterval { end.timeIntervalSince(start) }
    }

    private struct SleepSession {
        let interval: Interval
        let samples: [HKCategorySample]
        let totalSleepDuration: TimeInterval
    }

    private let healthStore: HKHealthStore
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "sheRuntime", category: "HealthKitProbe")
    private let sleepSessionGap: TimeInterval = 90 * 60

    init(healthStore: HKHealthStore = HKHealthStore()) {
        self.healthStore = healthStore
    }

    func requestReadAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw ManagerError.unavailable }
        let readTypes: Set<HKObjectType> = [
            try quantityType(.stepCount),
            try quantityType(.heartRateVariabilitySDNN),
            try quantityType(.restingHeartRate),
            try categoryType(.sleepAnalysis),
        ]
        try await healthStore.requestAuthorization(toShare: [], read: readTypes)
    }

    // Preserve the cumulative-sum query already verified on a physical iPhone.
    func loadTodaySteps(now: Date = Date()) async throws -> Int? {
        let stepType = try quantityType(.stepCount)
        let predicate = HKQuery.predicateForSamples(
            withStart: Calendar.current.startOfDay(for: now),
            end: now,
            options: .strictStartDate
        )
        let result: Double? = try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: stepType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error {
                    let nsError = error as NSError
                    if nsError.domain == HKErrorDomain,
                       nsError.code == HKError.errorNoData.rawValue {
                        continuation.resume(returning: nil)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                continuation.resume(returning: statistics?.sumQuantity()?.doubleValue(for: .count()))
            }
            healthStore.execute(query)
        }
        return result.map(Int.init)
    }

    func loadLatestHRV() async throws -> HRVReading? {
        let type = try quantityType(.heartRateVariabilitySDNN)
        guard let sample = try await loadLatestQuantitySample(type: type) else { return nil }
        return HRVReading(
            valueMilliseconds: sample.quantity.doubleValue(for: .secondUnit(with: .milli)),
            date: sample.endDate
        )
    }

    func loadLatestRestingHeartRate() async throws -> RestingHeartRateReading? {
        let type = try quantityType(.restingHeartRate)
        guard let sample = try await loadLatestQuantitySample(type: type) else { return nil }
        return RestingHeartRateReading(
            valueBPM: sample.quantity.doubleValue(for: .count().unitDivided(by: .minute())),
            date: sample.endDate
        )
    }

    func loadLatestPrimarySleep(now: Date = Date(), calendar: Calendar = .current) async throws -> SleepSummary? {
        let sleepType = try categoryType(.sleepAnalysis)
        let window = sleepQueryWindow(now: now, calendar: calendar)
        let predicate = HKQuery.predicateForSamples(withStart: window.start, end: window.end, options: [])

        let samples: [HKCategorySample] = try await withCheckedThrowingContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                continuation.resume(returning: samples as? [HKCategorySample] ?? [])
            }
            healthStore.execute(query)
        }

        for sample in samples {
            logger.info("Sleep sample source=\(sample.sourceRevision.source.name, privacy: .public) start=\(sample.startDate, privacy: .public) end=\(sample.endDate, privacy: .public) value=\(sample.value, privacy: .public)")
        }

        let validSamples = samples.filter {
            $0.endDate > window.start && $0.startDate < window.end && sleepStage(for: $0) != nil
        }
        guard !validSamples.isEmpty else { return nil }

        let sessions = makeSleepSessions(from: validSamples, clippedTo: window)
        guard let primary = sessions.max(by: {
            $0.totalSleepDuration == $1.totalSleepDuration
                ? $0.interval.end < $1.interval.end
                : $0.totalSleepDuration < $1.totalSleepDuration
        }), primary.totalSleepDuration > 0 else { return nil }

        let stages = SleepStage.allCases.map { stage in
            let intervals = primary.samples.compactMap { sample -> Interval? in
                guard sleepStage(for: sample) == stage else { return nil }
                return clippedInterval(start: sample.startDate, end: sample.endDate, to: primary.interval)
            }
            return SleepStageDuration(stage: stage, duration: mergedDuration(intervals))
        }
        return SleepSummary(
            startDate: primary.interval.start,
            endDate: primary.interval.end,
            totalSleepDuration: primary.totalSleepDuration,
            stages: stages
        )
    }

    private func loadLatestQuantitySample(type: HKQuantityType) async throws -> HKQuantitySample? {
        try await withCheckedThrowingContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) {
                _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                continuation.resume(returning: samples?.first as? HKQuantitySample)
            }
            healthStore.execute(query)
        }
    }

    private func sleepQueryWindow(now: Date, calendar: Calendar) -> Interval {
        let today = calendar.startOfDay(for: now)
        let noon = calendar.date(byAdding: .hour, value: 12, to: today)!
        return Interval(start: calendar.date(byAdding: .day, value: -1, to: noon)!, end: noon)
    }

    private func makeSleepSessions(from samples: [HKCategorySample], clippedTo window: Interval) -> [SleepSession] {
        let sessionIntervals = merge(samples.compactMap {
            clippedInterval(start: $0.startDate, end: $0.endDate, to: window)
        }, maximumGap: sleepSessionGap)

        return sessionIntervals.map { session in
            let sessionSamples = samples.filter { $0.endDate > session.start && $0.startDate < session.end }
            let asleepIntervals = sessionSamples.compactMap { sample -> Interval? in
                guard let stage = sleepStage(for: sample), stage.countsAsSleep else { return nil }
                return clippedInterval(start: sample.startDate, end: sample.endDate, to: session)
            }
            return SleepSession(
                interval: session,
                samples: sessionSamples,
                totalSleepDuration: mergedDuration(asleepIntervals)
            )
        }
    }

    private func sleepStage(for sample: HKCategorySample) -> SleepStage? {
        switch sample.value {
        case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue: .asleepUnspecified
        case HKCategoryValueSleepAnalysis.asleepCore.rawValue: .core
        case HKCategoryValueSleepAnalysis.asleepDeep.rawValue: .deep
        case HKCategoryValueSleepAnalysis.asleepREM.rawValue: .rem
        case HKCategoryValueSleepAnalysis.awake.rawValue: .awake
        case HKCategoryValueSleepAnalysis.inBed.rawValue: .inBed
        default: nil
        }
    }

    private func clippedInterval(start: Date, end: Date, to bounds: Interval) -> Interval? {
        let interval = Interval(start: max(start, bounds.start), end: min(end, bounds.end))
        return interval.end > interval.start ? interval : nil
    }

    private func mergedDuration(_ intervals: [Interval]) -> TimeInterval {
        merge(intervals, maximumGap: 0).reduce(0) { $0 + $1.duration }
    }

    private func merge(_ intervals: [Interval], maximumGap: TimeInterval) -> [Interval] {
        let sorted = intervals.sorted { $0.start < $1.start }
        guard var current = sorted.first else { return [] }
        var result: [Interval] = []
        for interval in sorted.dropFirst() {
            if interval.start.timeIntervalSince(current.end) <= maximumGap {
                current.end = max(current.end, interval.end)
            } else {
                result.append(current)
                current = interval
            }
        }
        result.append(current)
        return result
    }

    private func quantityType(_ identifier: HKQuantityTypeIdentifier) throws -> HKQuantityType {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else {
            throw ManagerError.missingDataType(identifier.rawValue)
        }
        return type
    }

    private func categoryType(_ identifier: HKCategoryTypeIdentifier) throws -> HKCategoryType {
        guard let type = HKCategoryType.categoryType(forIdentifier: identifier) else {
            throw ManagerError.missingDataType(identifier.rawValue)
        }
        return type
    }
}

private extension SleepStage {
    var countsAsSleep: Bool {
        switch self {
        case .asleepUnspecified, .core, .deep, .rem: true
        case .awake, .inBed: false
        }
    }
}
