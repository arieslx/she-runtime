import Foundation

struct HRVReading: Equatable {
    let valueMilliseconds: Double
    let date: Date
}

struct RestingHeartRateReading: Equatable {
    let valueBPM: Double
    let date: Date
}

enum SleepStage: String, CaseIterable, Identifiable {
    case asleepUnspecified, core, deep, rem, awake, inBed
    var id: Self { self }
}

struct SleepStageDuration: Equatable, Identifiable {
    let stage: SleepStage
    let duration: TimeInterval
    var id: SleepStage { stage }
}

struct SleepSummary: Equatable {
    let startDate: Date
    let endDate: Date
    let totalSleepDuration: TimeInterval
    let stages: [SleepStageDuration]

    func duration(for stage: SleepStage) -> TimeInterval {
        stages.first(where: { $0.stage == stage })?.duration ?? 0
    }
}

struct DailyHealthSummary: Equatable, Sendable {
    let date: Date
    let sleepDuration: TimeInterval?
    let latestHRVMs: Double?
    let restingHeartRateBPM: Double?
}

struct EnergyMapHealthData: Equatable, Sendable {
    let summary: DailyHealthSummary
    let hrvSamples: [HRVSample]
}
