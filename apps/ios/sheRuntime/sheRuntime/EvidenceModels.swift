import Foundation

struct EvidenceDocument: Decodable {
    let nowCard: EvidenceNowCard
    let rules: [EvidenceRule]
    let alerts: EvidenceAlerts
    let tips: EvidenceTips
    let storyCard: EvidenceStoryCard
    let observing: [EvidenceObservation]

    enum CodingKeys: String, CodingKey {
        case nowCard = "now_card"
        case rules, alerts, tips, observing
        case storyCard = "story_card"
    }
}

struct EvidenceNowCard: Decodable {
    let type: String
    let l1: String
    let linkRule: String

    enum CodingKeys: String, CodingKey {
        case type, l1
        case linkRule = "link_rule"
    }
}

struct EvidenceRule: Decodable, Identifiable {
    let id: String
    let recipe: String
    let status: String
    let priority: Int
    let l1: String
    let l2: String
    let l3: EvidenceRuleDetails
    let l4: String
}

struct EvidenceRuleDetails: Decodable {
    let phaseHRV: EvidencePhaseValues?
    let phaseRHR: EvidencePhaseValues?
    let confoundCheck: EvidenceConfoundCheck?
    let cycleCount: Int?
    let restedRHR: Double?
    let restedCount: Int?
    let shortRHR: Double?
    let shortCount: Int?
    let hrvByOnset: EvidenceOnsetValues?
    let enoughRatio: EvidenceEnoughRatio?

    enum CodingKeys: String, CodingKey {
        case phaseHRV = "phase_hrv"
        case phaseRHR = "phase_rhr"
        case confoundCheck = "confound_check"
        case cycleCount = "n_cycles"
        case restedRHR = "rested_rhr"
        case restedCount = "rested_n"
        case shortRHR = "short_rhr"
        case shortCount = "short_n"
        case hrvByOnset = "hrv_by_onset"
        case enoughRatio = "enough_ratio"
    }
}

struct EvidencePhaseValues: Decodable {
    let other: Double
    let premenstrual: Double
    let menses: Double
}

struct EvidenceConfoundCheck: Decodable {
    let description: String
    let premenstrualHRV: Double
    let premenstrualCount: Int
    let otherHRV: Double
    let otherCount: Int

    enum CodingKeys: String, CodingKey {
        case description = "desc"
        case premenstrualHRV = "pre_hrv"
        case premenstrualCount = "pre_n"
        case otherHRV = "other_hrv"
        case otherCount = "other_n"
    }
}

struct EvidenceOnsetValues: Decodable {
    let beforeMidnight: Double
    let oneToThree: Double
    let afterThree: Double

    enum CodingKeys: String, CodingKey {
        case beforeMidnight = "before0"
        case oneToThree = "h1to3"
        case afterThree = "after3"
    }
}

struct EvidenceEnoughRatio: Decodable {
    let beforeMidnight: Double
    let afterThree: Double

    enum CodingKeys: String, CodingKey {
        case beforeMidnight = "before0"
        case afterThree = "after3"
    }
}

struct EvidenceAlerts: Decodable {
    let titleKey: String
    let items: [EvidenceAlertItem]

    enum CodingKeys: String, CodingKey {
        case titleKey = "title_key"
        case items
    }
}

struct EvidenceAlertItem: Decodable, Identifiable {
    let text: String
    let linkRule: String?
    let details: EvidenceAlertDetails?
    let umbrella: String

    var id: String { linkRule ?? text }

    enum CodingKeys: String, CodingKey {
        case text, umbrella
        case linkRule = "link_rule"
        case details = "l3"
    }
}

struct EvidenceAlertDetails: Decodable {
    let hotThreshold: Double
    let hotDaysCount: Int

    enum CodingKeys: String, CodingKey {
        case hotThreshold = "hot_threshold"
        case hotDaysCount = "hot_days_n"
    }
}

struct EvidenceTips: Decodable {
    let titleKey: String
    let items: [EvidenceTipItem]

    enum CodingKeys: String, CodingKey {
        case titleKey = "title_key"
        case items
    }
}

struct EvidenceTipItem: Decodable, Identifiable {
    let rank: Int
    let text: String
    let linkRule: String?
    let details: EvidenceTipDetails?

    var id: String { "\(rank)-\(text)" }

    enum CodingKeys: String, CodingKey {
        case rank, text
        case linkRule = "link_rule"
        case details = "l3"
    }
}

struct EvidenceTipDetails: Decodable {
    let nextHRVBySteps: EvidenceStepValues

    enum CodingKeys: String, CodingKey {
        case nextHRVBySteps = "next_hrv_by_steps"
    }
}

struct EvidenceStepValues: Decodable {
    let low: Double
    let mid: Double
    let high: Double
}

struct EvidenceStoryCard: Decodable {
    let l1: String
    let details: EvidenceStoryDetails

    enum CodingKeys: String, CodingKey {
        case l1
        case details = "l3"
    }
}

struct EvidenceStoryDetails: Decodable {
    let hourlySeatedHR: [String: Double]
    let morningMedian: Double
    let afternoonMedian: Double

    enum CodingKeys: String, CodingKey {
        case hourlySeatedHR = "hourly_seated_hr"
        case morningMedian = "am_median"
        case afternoonMedian = "pm_median"
    }
}

struct EvidenceObservation: Decodable, Identifiable {
    let text: String
    let details: EvidenceObservationDetails?
    let ask: String

    var id: String { ask }

    enum CodingKeys: String, CodingKey {
        case text, ask
        case details = "l3"
    }
}

struct EvidenceObservationDetails: Decodable {
    let wednesdaySleepHours: Double

    enum CodingKeys: String, CodingKey {
        case wednesdaySleepHours = "wed_sleep_h"
    }
}

enum EvidenceLibrary {
    static func load() -> EvidenceDocument? {
        guard let url = Bundle.main.url(forResource: "evidence_zh", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(EvidenceDocument.self, from: data)
    }
}
