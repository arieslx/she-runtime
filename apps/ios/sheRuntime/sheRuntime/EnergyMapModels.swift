import Foundation

struct HRVSample: Equatable, Sendable {
    let valueMs: Double
    let startDate: Date
    let endDate: Date
    let sourceName: String
}

struct HRVBaseline: Equatable, Sendable {
    let center: Double?
    let scale: Double?
    let dayCount: Int
    let sampleCount: Int

    var isReliable: Bool {
        center != nil && scale != nil && dayCount >= 5 && sampleCount >= 10
    }
}

enum EnergyState: Equatable, Sendable {
    case high
    case normal
    case low
    case insufficientData
}

enum PointKind: Equatable, Sendable {
    case observed
    case estimated
}

struct EnergyMapPoint: Identifiable, Equatable, Sendable {
    let id: UUID
    let date: Date
    let score: Double
    let kind: PointKind
    let supportingSampleCount: Int

    init(
        id: UUID = UUID(),
        date: Date,
        score: Double,
        kind: PointKind,
        supportingSampleCount: Int
    ) {
        self.id = id
        self.date = date
        self.score = score
        self.kind = kind
        self.supportingSampleCount = supportingSampleCount
    }

    static func == (lhs: EnergyMapPoint, rhs: EnergyMapPoint) -> Bool {
        lhs.date == rhs.date && lhs.score == rhs.score && lhs.kind == rhs.kind
            && lhs.supportingSampleCount == rhs.supportingSampleCount
    }
}

struct EnergyMapResult: Equatable, Sendable {
    let points: [EnergyMapPoint]
    let currentScore: Double?
    let currentState: EnergyState
    let latestSampleDate: Date?
    let freshness: Double
    let bestFocusWindow: DateInterval?
    let lowWindow: DateInterval?
    let baselineDayCount: Int
    let baselineSampleCount: Int
    let hasReliableBaseline: Bool
    let hasEstimatedTrend: Bool
    let historicalDayCount: Int
}
