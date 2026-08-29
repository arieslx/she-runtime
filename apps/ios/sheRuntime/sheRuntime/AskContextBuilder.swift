import Foundation

struct AskCompactContext: Encodable, Equatable, Sendable {
    var schemaVersion: Int
    var generatedAt: String
    var subjectiveEvents: [AskSubjectiveContextEvent]
    var healthSummary: AskHealthSummary

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generatedAt = "generated_at"
        case subjectiveEvents = "subjective_events"
        case healthSummary = "health_summary"
    }
}

struct AskSubjectiveContextEvent: Encodable, Equatable, Sendable {
    var sourceEventID: String
    var occurredAt: String
    var timezone: String?
    var source: String
    var topicKey: String
    var confirmedText: String
    var extractionStatus: String
    var extractionVersion: String?
    var extractionConfidence: Double?
    var confirmationStatus: String
    var revision: Int
    var annotations: [AskContextAnnotation]

    enum CodingKeys: String, CodingKey {
        case sourceEventID = "source_event_id"
        case occurredAt = "occurred_at"
        case timezone
        case source
        case topicKey = "topic_key"
        case confirmedText = "confirmed_text"
        case extractionStatus = "extraction_status"
        case extractionVersion = "extraction_version"
        case extractionConfidence = "extraction_confidence"
        case confirmationStatus = "confirmation_status"
        case revision
        case annotations
    }
}

struct AskContextAnnotation: Encodable, Equatable, Sendable {
    var annotationID: String
    var dimension: String
    var value: String
    var confidence: Double?
    var extractorVersion: String?
    var confirmationStatus: String

    enum CodingKeys: String, CodingKey {
        case annotationID = "annotation_id"
        case dimension
        case value
        case confidence
        case extractorVersion = "extractor_version"
        case confirmationStatus = "confirmation_status"
    }
}

struct AskHealthSummary: Encodable, Equatable, Sendable {
    var windowStart: String
    var windowEnd: String
    var effectiveDayCount: Int
    var latestRecordAt: String?
    var isStale: Bool
    var metrics: [AskMetricSummary]

    enum CodingKeys: String, CodingKey {
        case windowStart = "window_start"
        case windowEnd = "window_end"
        case effectiveDayCount = "effective_day_count"
        case latestRecordAt = "latest_record_at"
        case isStale = "is_stale"
        case metrics
    }
}

struct AskMetricSummary: Encodable, Equatable, Sendable {
    var metricKey: String
    var sampleCount: Int
    var latestValue: Double
    var medianValue: Double
    var unitKey: String

    enum CodingKeys: String, CodingKey {
        case metricKey = "metric_key"
        case sampleCount = "sample_count"
        case latestValue = "latest_value"
        case medianValue = "median_value"
        case unitKey = "unit_key"
    }
}

protocol AskContextProviding: Sendable {
    func makeContext(
        subjectiveEvents: [SubjectiveEvent],
        now: Date
    ) async -> AskCompactContext
}

struct LocalAskContextProvider: AskContextProviding {
    typealias DailyProvider = @Sendable () async throws -> [DailyRecord]

    private let dailyProvider: DailyProvider

    init(dailyProvider: @escaping DailyProvider = {
        try await HealthDataStore.shared.dailyRecords()
    }) {
        self.dailyProvider = dailyProvider
    }

    func makeContext(
        subjectiveEvents: [SubjectiveEvent],
        now: Date = Date()
    ) async -> AskCompactContext {
        let daily = (try? await dailyProvider()) ?? []
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let healthStart = calendar.date(byAdding: .day, value: -27, to: calendar.startOfDay(for: now))
            ?? now.addingTimeInterval(-27 * 86_400)
        let subjectiveStart = calendar.date(byAdding: .day, value: -89, to: calendar.startOfDay(for: now))
            ?? now.addingTimeInterval(-89 * 86_400)
        let recentDaily = daily.filter { $0.date >= healthStart && $0.date <= now }
        let recentSubjective = subjectiveEvents
            .filter {
                $0.occurredAt >= subjectiveStart
                    && $0.occurredAt <= now
                    && ($0.confirmationStatus == .confirmed || $0.confirmationStatus == .corrected)
            }
            .sorted { $0.occurredAt > $1.occurredAt }
            .prefix(12)
            .map(Self.contextEvent)

        return AskCompactContext(
            schemaVersion: 1,
            generatedAt: Self.timestamp(now),
            subjectiveEvents: Array(recentSubjective),
            healthSummary: Self.healthSummary(records: recentDaily, start: healthStart, now: now)
        )
    }

    private static func contextEvent(_ event: SubjectiveEvent) -> AskSubjectiveContextEvent {
        let confirmedAnnotations = event.annotations
            .filter {
                $0.confirmationStatus == .userConfirmed || $0.confirmationStatus == .userCorrected
            }
            .prefix(8)
            .map { annotation in
                AskContextAnnotation(
                    annotationID: annotation.id,
                    dimension: annotation.dimension.rawValue,
                    value: clipped(annotation.value, limit: 80),
                    confidence: annotation.confidence,
                    extractorVersion: annotation.extractorVersion,
                    confirmationStatus: annotation.confirmationStatus.rawValue
                )
            }

        return AskSubjectiveContextEvent(
            sourceEventID: event.id.uuidString,
            occurredAt: timestamp(event.occurredAt),
            timezone: event.timezoneIdentifier,
            source: event.source.rawValue,
            topicKey: clipped(event.topicKey, limit: 100),
            confirmedText: clipped(event.confirmedText, limit: 240),
            extractionStatus: event.extractionStatus.rawValue,
            extractionVersion: event.extractionVersion,
            extractionConfidence: event.extractionConfidence,
            confirmationStatus: event.confirmationStatus.rawValue,
            revision: event.revision,
            annotations: confirmedAnnotations
        )
    }

    private static func healthSummary(
        records: [DailyRecord],
        start: Date,
        now: Date
    ) -> AskHealthSummary {
        let ordered = records.sorted { $0.date < $1.date }
        var metrics: [AskMetricSummary] = []

        func add(_ key: String, unit: String, values: [Double]) {
            guard let latest = values.last, let median = median(values) else { return }
            metrics.append(AskMetricSummary(
                metricKey: key,
                sampleCount: values.count,
                latestValue: latest,
                medianValue: median,
                unitKey: unit
            ))
        }

        add("sleep_hours", unit: "hours", values: ordered.compactMap(\.sleepHours))
        add("sleep_onset_minutes", unit: "minutes_after_midnight", values: ordered.compactMap { $0.sleepOnsetMinutes.map(Double.init) })
        add("hrv", unit: "milliseconds", values: ordered.compactMap(\.hrv))
        add("resting_heart_rate", unit: "beats_per_minute", values: ordered.compactMap(\.restingHeartRate))
        add("wrist_temperature", unit: "celsius", values: ordered.compactMap(\.wristTemp))
        add("respiratory_rate", unit: "breaths_per_minute", values: ordered.compactMap(\.respiratoryRate))
        add("steps", unit: "steps", values: ordered.compactMap { $0.steps.map(Double.init) })
        add("headphone_hours", unit: "hours", values: ordered.compactMap(\.headphoneHours))
        add("daylight_minutes", unit: "minutes", values: ordered.compactMap(\.daylightMinutes))
        add("mindful_minutes", unit: "minutes", values: ordered.compactMap(\.mindfulMinutes))
        let mensesDays = ordered.filter(\.hasMenses).count
        if mensesDays > 0 {
            add("menses_days", unit: "days", values: [Double(mensesDays)])
        }

        let latestDate = ordered.last?.date
        let staleCutoff = now.addingTimeInterval(-3 * 86_400)
        return AskHealthSummary(
            windowStart: timestamp(start),
            windowEnd: timestamp(now),
            effectiveDayCount: ordered.filter(Self.isEffectiveDay).count,
            latestRecordAt: latestDate.map { timestamp($0) },
            isStale: latestDate.map { $0 < staleCutoff } ?? true,
            metrics: metrics
        )
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    nonisolated private static func timestamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    nonisolated private static func isEffectiveDay(_ record: DailyRecord) -> Bool {
        record.sleepHours != nil || record.sleepOnsetMinutes != nil || record.hrv != nil
            || record.restingHeartRate != nil || record.wristTemp != nil
            || record.respiratoryRate != nil || record.steps != nil || record.hasMenses
            || record.headphoneHours != nil || record.daylightMinutes != nil
            || record.mindfulMinutes != nil
    }

    private static func clipped(_ value: String, limit: Int) -> String {
        String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
    }
}
