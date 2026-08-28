import Foundation

struct EnergyMapCalculator: Sendable {
    let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func calculate(samples rawSamples: [HRVSample], targetDate: Date, now: Date) -> EnergyMapResult {
        let samples = rawSamples.filter(Self.isValid).sorted { $0.startDate < $1.startDate }
        let targetStart = calendar.startOfDay(for: targetDate)
        let targetEnd = calendar.date(byAdding: .day, value: 1, to: targetStart)!
        let baseline = makeBaseline(samples: samples, targetDate: targetDate)

        guard baseline.isReliable else {
            return emptyResult(baseline: baseline)
        }

        let targetSamples = samples.filter { $0.startDate >= targetStart && $0.startDate < targetEnd }
        let observed = observedPoints(samples: targetSamples, baseline: baseline, dayStart: targetStart)
        let isToday = calendar.isDate(targetDate, inSameDayAs: now)
        let current = isToday ? currentStatus(samples: targetSamples, baseline: baseline, now: now) : nil
        let historical = historicalSlotMedians(samples: samples, before: targetStart)
        let estimates = isToday
            ? estimatedPoints(observed: observed, historical: historical, now: now, hasTodaySamples: !targetSamples.isEmpty)
            : []
        let windows = exploratoryWindows(historical: historical, dayStart: targetStart)

        return EnergyMapResult(
            points: (observed + estimates).sorted { $0.date < $1.date },
            currentScore: current?.score,
            currentState: current?.state ?? .insufficientData,
            latestSampleDate: current?.date,
            freshness: current?.freshness ?? 0,
            bestFocusWindow: windows?.best,
            lowWindow: windows?.low,
            baselineDayCount: baseline.dayCount,
            baselineSampleCount: baseline.sampleCount,
            hasReliableBaseline: true,
            hasEstimatedTrend: !estimates.isEmpty,
            historicalDayCount: historical.validDayCount
        )
    }

    func makeBaseline(samples rawSamples: [HRVSample], targetDate: Date) -> HRVBaseline {
        let targetStart = calendar.startOfDay(for: targetDate)
        let valid = rawSamples.filter(Self.isValid).filter { $0.startDate < targetStart }
        let grouped = Dictionary(grouping: valid) { calendar.startOfDay(for: $0.startDate) }
        let days = grouped.keys.sorted(by: >).prefix(14)
        let selected = days.compactMap { grouped[$0] }
        let dailyMedians = selected.compactMap { median($0.map { log($0.valueMs) }) }
        let sampleCount = selected.reduce(0) { $0 + $1.count }

        guard dailyMedians.count >= 5, sampleCount >= 10,
              let center = median(dailyMedians),
              let mad = median(dailyMedians.map { abs($0 - center) }) else {
            return HRVBaseline(center: nil, scale: nil, dayCount: dailyMedians.count, sampleCount: sampleCount)
        }
        return HRVBaseline(
            center: center,
            scale: max(1.4826 * mad, 0.08),
            dayCount: dailyMedians.count,
            sampleCount: sampleCount
        )
    }

    func score(valueMs: Double, baseline: HRVBaseline) -> Double? {
        guard Self.isValidValue(valueMs), baseline.isReliable,
              let center = baseline.center, let scale = baseline.scale else { return nil }
        let z = min(2.5, max(-2.5, (log(valueMs) - center) / scale))
        return min(95, max(5, 50 + 18 * z))
    }

    private func observedPoints(samples: [HRVSample], baseline: HRVBaseline, dayStart: Date) -> [EnergyMapPoint] {
        let scored = samples.compactMap { sample -> (date: Date, score: Double)? in
            score(valueMs: sample.valueMs, baseline: baseline).map { (sample.startDate, $0) }
        }
        guard !scored.isEmpty else { return [] }
        let nodes = chartNodes(dayStart: dayStart)
        var values: [Double?] = nodes.map { node in
            let nearby = scored.compactMap { sample -> (Double, Double)? in
                let distance = abs(sample.date.timeIntervalSince(node)) / 60
                guard distance <= 90 else { return nil }
                let weight = exp(-(distance * distance) / (2 * 60 * 60))
                return (sample.score, weight)
            }
            let weight = nearby.reduce(0) { $0 + $1.1 }
            return weight > 0 ? nearby.reduce(0) { $0 + $1.0 * $1.1 } / weight : nil
        }
        let supportCounts = nodes.map { node in
            scored.filter { abs($0.date.timeIntervalSince(node)) <= 90 * 60 }.count
        }

        for index in values.indices where values[index] == nil {
            guard let left = values[..<index].lastIndex(where: { $0 != nil }),
                  let right = values[index...].firstIndex(where: { $0 != nil }),
                  let previousSample = scored.last(where: { $0.date <= nodes[index] }),
                  let nextSample = scored.first(where: { $0.date >= nodes[index] }),
                  nextSample.date.timeIntervalSince(previousSample.date) <= 3 * 60 * 60,
                  let leftValue = values[left], let rightValue = values[right] else { continue }
            let ratio = Double(index - left) / Double(right - left)
            values[index] = leftValue + (rightValue - leftValue) * ratio
        }

        let smoothed = values.indices.map { index -> Double? in
            guard values[index] != nil else { return nil }
            let range = max(0, index - 1)...min(values.count - 1, index + 1)
            let local = range.compactMap { values[$0] }
            return local.isEmpty ? nil : min(95, max(5, local.reduce(0, +) / Double(local.count)))
        }
        return nodes.indices.compactMap { index in
            smoothed[index].map {
                EnergyMapPoint(date: nodes[index], score: $0, kind: .observed, supportingSampleCount: supportCounts[index])
            }
        }
    }

    private struct CurrentStatus {
        let score: Double
        let state: EnergyState
        let date: Date
        let freshness: Double
    }

    private func currentStatus(samples: [HRVSample], baseline: HRVBaseline, now: Date) -> CurrentStatus? {
        guard let latest = samples.min(by: {
            abs($0.startDate.timeIntervalSince(now)) < abs($1.startDate.timeIntervalSince(now))
        }), let value = score(valueMs: latest.valueMs, baseline: baseline) else { return nil }
        let hours = abs(now.timeIntervalSince(latest.startDate)) / 3600
        return CurrentStatus(
            score: value,
            state: hours > 6 ? .insufficientData : state(for: value),
            date: latest.startDate,
            freshness: exp(-hours / 4)
        )
    }

    private struct HistoricalSlots {
        let medians: [Int: Double]
        let dayCounts: [Int: Int]
        let validDayCount: Int
    }

    private func historicalSlotMedians(samples: [HRVSample], before targetStart: Date) -> HistoricalSlots {
        let historyStart = calendar.date(byAdding: .day, value: -28, to: targetStart)!
        let days = Set(samples.filter { $0.startDate >= historyStart && $0.startDate < targetStart }
            .map { calendar.startOfDay(for: $0.startDate) }).sorted()
        var slotValues: [Int: [Double]] = [:]
        var usableDays = 0

        for day in days {
            let baseline = makeBaseline(samples: samples, targetDate: day)
            guard baseline.isReliable else { continue }
            let end = calendar.date(byAdding: .day, value: 1, to: day)!
            let daySamples = samples.filter { $0.startDate >= day && $0.startDate < end }
            var daySlots: [Int: [Double]] = [:]
            for sample in daySamples {
                guard let slot = slotIndex(for: sample.startDate, dayStart: day),
                      let sampleScore = score(valueMs: sample.valueMs, baseline: baseline) else { continue }
                daySlots[slot, default: []].append(sampleScore)
            }
            guard !daySlots.isEmpty else { continue }
            usableDays += 1
            for (slot, values) in daySlots {
                if let value = median(values) { slotValues[slot, default: []].append(value) }
            }
        }
        return HistoricalSlots(
            medians: slotValues.compactMapValues { $0.count >= 5 ? median($0) : nil },
            dayCounts: slotValues.mapValues(\.count),
            validDayCount: usableDays
        )
    }

    private func estimatedPoints(
        observed: [EnergyMapPoint], historical: HistoricalSlots, now: Date, hasTodaySamples: Bool
    ) -> [EnergyMapPoint] {
        guard historical.validDayCount >= 7, hasTodaySamples,
              let last = observed.max(by: { $0.date < $1.date }) else { return [] }
        return historical.medians.keys.sorted().compactMap { slot in
            let date = calendar.date(byAdding: .minute, value: 8 * 60 + slot * 30, to: calendar.startOfDay(for: now))!
            guard date > last.date, date > now, let historicalScore = historical.medians[slot] else { return nil }
            let alpha = min(1, date.timeIntervalSince(last.date) / (90 * 60))
            let blended = last.score * (1 - alpha) + historicalScore * alpha
            return EnergyMapPoint(
                date: date,
                score: min(95, max(5, blended)),
                kind: .estimated,
                supportingSampleCount: historical.dayCounts[slot] ?? 0
            )
        }
    }

    private func exploratoryWindows(
        historical: HistoricalSlots, dayStart: Date
    ) -> (best: DateInterval, low: DateInterval)? {
        guard historical.validDayCount >= 7 else { return nil }
        var candidates: [(slot: Int, average: Double)] = []
        for slot in 0...22 {
            let values = (slot...slot + 2).compactMap { historical.medians[$0] }
            guard values.count == 3 else { continue }
            candidates.append((slot, values.reduce(0, +) / 3))
        }
        guard let best = candidates.max(by: { $0.average < $1.average }),
              let low = candidates.min(by: { $0.average < $1.average }),
              best.average - low.average >= 8 else { return nil }
        func interval(_ slot: Int) -> DateInterval {
            let start = calendar.date(byAdding: .minute, value: 8 * 60 + slot * 30, to: dayStart)!
            return DateInterval(start: start, duration: 90 * 60)
        }
        return (interval(best.slot), interval(low.slot))
    }

    private func chartNodes(dayStart: Date) -> [Date] {
        (0...24).map { calendar.date(byAdding: .minute, value: 8 * 60 + $0 * 30, to: dayStart)! }
    }

    private func slotIndex(for date: Date, dayStart: Date) -> Int? {
        let minutes = date.timeIntervalSince(dayStart) / 60
        guard minutes >= 8 * 60, minutes <= 20 * 60 else { return nil }
        return min(24, max(0, Int((minutes - 8 * 60) / 30)))
    }

    func state(for score: Double) -> EnergyState {
        if score >= 74 { return .full }
        if score >= 62 { return .good }
        if score >= 38 { return .steady }
        if score >= 26 { return .dipping }
        return .low
    }

    private func emptyResult(baseline: HRVBaseline) -> EnergyMapResult {
        EnergyMapResult(
            points: [], currentScore: nil, currentState: .insufficientData,
            latestSampleDate: nil, freshness: 0, bestFocusWindow: nil, lowWindow: nil,
            baselineDayCount: baseline.dayCount, baselineSampleCount: baseline.sampleCount,
            hasReliableBaseline: false, hasEstimatedTrend: false, historicalDayCount: 0
        )
    }

    private func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    private nonisolated static func isValid(_ sample: HRVSample) -> Bool { isValidValue(sample.valueMs) }
    private nonisolated static func isValidValue(_ value: Double) -> Bool { value.isFinite && value >= 5 && value <= 500 }
}
