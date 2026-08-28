import Foundation

struct HealthSampleInterval: Equatable, Sendable {
    let start: Date
    let end: Date
    let stage: SleepStage
    let sourceName: String

    var duration: TimeInterval { end.timeIntervalSince(start) }
}

enum DailyHealthSummaryLogic {
    static func sleepWindow(for targetDate: Date, calendar: Calendar) -> DateInterval {
        let dayStart = calendar.startOfDay(for: targetDate)
        let windowEnd = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: dayStart)!
        let windowStart = calendar.date(byAdding: .day, value: -1, to: windowEnd)!
        return DateInterval(start: windowStart, end: windowEnd)
    }

    static func dayWindow(for targetDate: Date, now: Date, calendar: Calendar) -> DateInterval {
        let dayStart = calendar.startOfDay(for: targetDate)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        let end = calendar.isDate(targetDate, inSameDayAs: now) ? min(now, nextDay) : nextDay
        return DateInterval(start: dayStart, end: end)
    }

    static func primarySleepDuration(
        from samples: [HealthSampleInterval],
        in window: DateInterval,
        maximumSessionGap: TimeInterval = 90 * 60
    ) -> TimeInterval? {
        let clippedSamples = samples.compactMap { sample -> HealthSampleInterval? in
            guard let interval = clippedInterval(start: sample.start, end: sample.end, to: window) else { return nil }
            return HealthSampleInterval(
                start: interval.start,
                end: interval.end,
                stage: sample.stage,
                sourceName: sample.sourceName
            )
        }
        let sessionIntervals = merge(
            clippedSamples.compactMap {
                $0.stage.countsAsActualSleep ? DateInterval(start: $0.start, end: $0.end) : nil
            },
            maximumGap: maximumSessionGap
        )
        let duration = sessionIntervals.map { session -> TimeInterval in
            let asleepIntervals = clippedSamples.compactMap { sample -> DateInterval? in
                guard sample.stage.countsAsActualSleep else { return nil }
                return clippedInterval(start: sample.start, end: sample.end, to: session)
            }
            return mergedDuration(asleepIntervals)
        }.max() ?? 0
        return duration > 0 ? duration : nil
    }

    static func mergedSleepDuration(from samples: [HealthSampleInterval], in window: DateInterval) -> TimeInterval? {
        let asleepIntervals = samples.compactMap { sample -> DateInterval? in
            guard sample.stage.countsAsActualSleep else { return nil }
            return clippedInterval(start: sample.start, end: sample.end, to: window)
        }
        let duration = mergedDuration(asleepIntervals)
        return duration > 0 ? duration : nil
    }

    static func latestPositiveFiniteValue<T>(
        from samples: [T],
        value: (T) -> Double,
        endDate: (T) -> Date,
        in window: DateInterval
    ) -> Double? {
        samples
            .filter { endDate($0) >= window.start && endDate($0) < window.end }
            .sorted { endDate($0) > endDate($1) }
            .lazy
            .map(value)
            .first { $0.isFinite && $0 > 0 }
    }

    static func formatSleep(_ duration: TimeInterval?) -> (value: String, unit: String) {
        guard let duration, duration > 0 else { return ("--", "") }
        let totalMinutes = Int((duration / 60).rounded())
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? ("\(hours)h \(minutes)", "m") : ("\(minutes)", "m")
    }

    static func formatMilliseconds(_ value: Double?) -> (value: String, unit: String) {
        guard let value, value.isFinite, value > 0 else { return ("--", "ms") }
        return ("\(Int(value.rounded()))", "ms")
    }

    static func formatBPM(_ value: Double?) -> (value: String, unit: String) {
        guard let value, value.isFinite, value > 0 else { return ("--", "bpm") }
        return ("\(Int(value.rounded()))", "bpm")
    }

    private static func clippedInterval(start: Date, end: Date, to bounds: DateInterval) -> DateInterval? {
        let interval = DateInterval(start: max(start, bounds.start), end: min(end, bounds.end))
        return interval.end > interval.start ? interval : nil
    }

    private static func mergedDuration(_ intervals: [DateInterval]) -> TimeInterval {
        merge(intervals, maximumGap: 0).reduce(0) { $0 + $1.duration }
    }

    private static func merge(_ intervals: [DateInterval], maximumGap: TimeInterval) -> [DateInterval] {
        let sorted = intervals.sorted { $0.start < $1.start }
        guard var current = sorted.first else { return [] }
        var result: [DateInterval] = []
        for interval in sorted.dropFirst() {
            if interval.start.timeIntervalSince(current.end) <= maximumGap {
                current = DateInterval(start: current.start, end: max(current.end, interval.end))
            } else {
                result.append(current)
                current = interval
            }
        }
        result.append(current)
        return result
    }
}

extension SleepStage {
    var countsAsActualSleep: Bool {
        switch self {
        case .asleepUnspecified, .core, .deep, .rem: true
        case .awake, .inBed: false
        }
    }
}
