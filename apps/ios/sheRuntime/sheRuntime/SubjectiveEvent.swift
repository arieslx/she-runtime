import Foundation
import SwiftData

// MARK: - Stable subjective-event contract

enum SubjectiveExtractionStatus: String, Codable, Sendable {
    case pending
    case completed
    case failed
    case unknown
}

enum SubjectiveConfirmationStatus: String, Codable, Sendable {
    case confirmed
    case corrected
    case unreviewed
    case unknown
}

enum SubjectiveAnnotationStatus: String, Codable, Sendable {
    case pending
    case userConfirmed
    case userCorrected
    case userRejected
}

enum SubjectiveAnnotationKind: String, Codable, Sendable {
    case tag
    case entity
}

enum SubjectiveSemanticDimension: String, Codable, CaseIterable, Sendable {
    case bodySensation = "body_sensation"
    case emotion
    case cognition
    case behavior
    case environment
    case cycle
    case medicationOrCare = "medication_or_care"
    case planOrConcern = "plan_or_concern"
    case unknown
}

struct SubjectiveAnnotation: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var kind: SubjectiveAnnotationKind
    var dimension: SubjectiveSemanticDimension
    var value: String
    var confidence: Double?
    var extractorVersion: String?
    var confirmationStatus: SubjectiveAnnotationStatus
}

/// Versioned metadata stored inside TimelineRecord.tagsData.
/// The SwiftData columns stay unchanged, so existing stores do not need a schema migration.
struct SubjectiveRecordMetadata: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1
    static let legacyMockTags = ["Work", "Meeting", "Mental fatigue", "Energy ↓"]

    var schemaVersion: Int
    var topicKey: String
    var timezoneIdentifier: String?
    var extractionStatus: SubjectiveExtractionStatus
    var extractionVersion: String?
    var extractionConfidence: Double?
    var confirmationStatus: SubjectiveConfirmationStatus
    var revision: Int
    var updatedAt: Date
    var annotations: [SubjectiveAnnotation]

    static func pending(
        topicKey: String,
        timezoneIdentifier: String? = TimeZone.current.identifier,
        confirmationStatus: SubjectiveConfirmationStatus,
        updatedAt: Date
    ) -> SubjectiveRecordMetadata {
        SubjectiveRecordMetadata(
            schemaVersion: currentSchemaVersion,
            topicKey: topicKey,
            timezoneIdentifier: timezoneIdentifier,
            extractionStatus: .pending,
            extractionVersion: nil,
            extractionConfidence: nil,
            confirmationStatus: confirmationStatus,
            revision: 1,
            updatedAt: updatedAt,
            annotations: []
        )
    }

    static func decode(_ data: Data, fallbackDate: Date) -> SubjectiveRecordMetadata {
        if let payload = try? JSONDecoder().decode(SubjectiveRecordMetadata.self, from: data) {
            return payload
        }

        // Compatibility with records saved before the subjective-event contract.
        // Legacy strings have no extractor version/confidence, so they remain pending.
        let legacyValues = (try? JSONDecoder().decode([String].self, from: data)) ?? []
        let safeValues = legacyValues == legacyMockTags ? [] : legacyValues
        let annotations = safeValues.enumerated().map { index, value in
            SubjectiveAnnotation(
                id: "legacy-\(index)",
                kind: .tag,
                dimension: .unknown,
                value: value,
                confidence: nil,
                extractorVersion: nil,
                confirmationStatus: .pending
            )
        }
        return SubjectiveRecordMetadata(
            schemaVersion: 0,
            topicKey: "legacy.unknown",
            timezoneIdentifier: nil,
            extractionStatus: .pending,
            extractionVersion: nil,
            extractionConfidence: nil,
            confirmationStatus: .unknown,
            revision: 1,
            updatedAt: fallbackDate,
            annotations: annotations
        )
    }
}

enum SubjectiveEventSource: String, Codable, Sendable {
    case iPhoneVoice = "iphone_voice"
    case stopWatchVoice = "stopwatch_voice"
    case ask = "ask"
    case onboarding = "onboarding"
    case legacy = "legacy"
    case unknown

    init(timelineSource: String) {
        switch timelineSource {
        case TimelineRecordSource.iPhoneVoice:
            self = .iPhoneVoice
        case TimelineRecordSource.stopWatch:
            self = .stopWatchVoice
        case TimelineRecordSource.ask:
            self = .ask
        case TimelineRecordSource.onboarding:
            self = .onboarding
        case TimelineRecordSource.legacySubjectiveStore:
            self = .legacy
        default:
            self = .unknown
        }
    }
}

/// Immutable value read by Ask and EvidenceEngine. Model objects never leave MainActor.
struct SubjectiveEvent: Identifiable, Equatable, Sendable {
    var id: UUID
    var occurredAt: Date
    var timezoneIdentifier: String?
    var source: SubjectiveEventSource
    var topicKey: String
    var rawText: String
    var confirmedText: String
    var extractionStatus: SubjectiveExtractionStatus
    var extractionVersion: String?
    var extractionConfidence: Double?
    var confirmationStatus: SubjectiveConfirmationStatus
    var revision: Int
    var annotations: [SubjectiveAnnotation]

    var asNote: SubjectiveNote {
        SubjectiveNote(
            date: occurredAt,
            topicKey: topicKey,
            text: confirmedText,
            id: id.uuidString,
            source: source.rawValue,
            rawText: rawText,
            timezoneIdentifier: timezoneIdentifier,
            extractionStatus: extractionStatus,
            confirmationStatus: confirmationStatus,
            revision: revision
        )
    }
}

@MainActor
enum SubjectiveEventAdapter {
    static func activeEvents(from records: [TimelineRecord]) -> [SubjectiveEvent] {
        records
            .filter { record in
                record.saveStatus == TimelineRecordStatus.saved
                    && !record.isHidden
                    && TimelineRecordType.subjectiveTypes.contains(record.eventType)
                    && !record.confirmedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            .map(snapshot)
            .sorted { $0.occurredAt < $1.occurredAt }
    }

    static func notes(from records: [TimelineRecord]) -> [SubjectiveNote] {
        activeEvents(from: records)
            .filter {
                $0.confirmationStatus == .confirmed || $0.confirmationStatus == .corrected
            }
            .map(\.asNote)
    }

    static func changeFingerprint(for records: [TimelineRecord]) -> [String] {
        records
            .filter { TimelineRecordType.subjectiveTypes.contains($0.eventType) }
            .map { record in
                let metadata = record.subjectiveMetadata
                return [
                    record.id.uuidString,
                    record.saveStatus,
                    record.isHidden ? "hidden" : "visible",
                    String(metadata.revision),
                    String(record.confirmedText.hashValue)
                ].joined(separator: "|")
            }
            .sorted()
    }

    private static func snapshot(_ record: TimelineRecord) -> SubjectiveEvent {
        let metadata = record.subjectiveMetadata
        return SubjectiveEvent(
            id: record.id,
            occurredAt: record.createdAt,
            timezoneIdentifier: metadata.timezoneIdentifier,
            source: SubjectiveEventSource(timelineSource: record.source),
            topicKey: metadata.topicKey,
            rawText: record.rawTranscript,
            confirmedText: record.confirmedText,
            extractionStatus: metadata.extractionStatus,
            extractionVersion: metadata.extractionVersion,
            extractionConfidence: metadata.extractionConfidence,
            confirmationStatus: metadata.confirmationStatus,
            revision: metadata.revision,
            annotations: metadata.annotations
        )
    }
}

// MARK: - Ask / onboarding capture rules

enum SubjectiveInputOrigin: Equatable, Sendable {
    case ask
    case onboarding(promptKey: String)

    var promptKey: String? {
        if case .onboarding(let promptKey) = self { return promptKey }
        return nil
    }
}

enum SubjectiveCaptureReason: String, Equatable, Sendable {
    case onboardingAnswer
    case explicitSelfReport
    case personalHypothesis
    case ordinaryQuestion
    case empty
}

struct SubjectiveCaptureDecision: Equatable, Sendable {
    var shouldPersist: Bool
    var reason: SubjectiveCaptureReason
    var topicKey: String
}

enum SubjectiveInputClassifier {
    private static let hypothesisMarkers = [
        "我怀疑", "我猜", "我担心", "会不会是因为", "是不是因为",
        "I suspect", "I think it may", "I worry"
    ]

    private static let selfReportMarkers = [
        "我感觉", "我觉得", "我现在", "我今天", "我昨天", "我昨晚",
        "这几天我", "最近我", "刚刚我", "我刚", "我总是", "我经常", "我通常",
        "我一直", "我有点", "我很累", "我累", "我困", "我疼", "我痛",
        "我难受", "我不舒服", "我睡不着", "我没睡好", "我睡了", "我吃了",
        "我用了", "我试了", "我来月经", "我希望", "我想要",
        "I feel", "I felt", "I am ", "I'm ", "I have ", "I had ",
        "I slept", "I took", "I tried", "I hope", "I want to"
    ]

    private static let questionMarkers = [
        "?", "？", "为什么", "怎么样", "多少", "几点", "何时", "有没有",
        "能不能", "可以吗", "是否", "how ", "why ", "what ", "when "
    ]

    private static let assertiveStateMarkers = [
        "我感觉", "我觉得", "我有点", "我很累", "我累", "我困", "疼", "痛",
        "难受", "不舒服", "睡不着", "没睡好", "头晕", "恶心", "出血",
        "我睡了", "我吃了", "我用了", "我试了", "我来月经",
        "I feel", "I felt", "I'm ", "I have ", "I had ", "I slept", "I took"
    ]

    private static let personalAnchors = [
        "我", "最近", "今天", "昨天", "昨晚", "这几天", "刚刚", "总是",
        "I ", "I'm", "I've", "my ", "today", "last night", "recently"
    ]

    static func classify(_ rawText: String, origin: SubjectiveInputOrigin) -> SubjectiveCaptureDecision {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return SubjectiveCaptureDecision(shouldPersist: false, reason: .empty, topicKey: "unknown")
        }

        if case .onboarding(let promptKey) = origin {
            return SubjectiveCaptureDecision(
                shouldPersist: true,
                reason: .onboardingAnswer,
                topicKey: promptKey
            )
        }

        if hypothesisMarkers.contains(where: { text.localizedCaseInsensitiveContains($0) }) {
            return SubjectiveCaptureDecision(
                shouldPersist: true,
                reason: .personalHypothesis,
                topicKey: "ask.personal_hypothesis"
            )
        }

        let looksLikeQuestion = questionMarkers.contains {
            text.localizedCaseInsensitiveContains($0)
        }
        let alsoStatesAnExperience = personalAnchors.contains {
            text.localizedCaseInsensitiveContains($0)
        } && assertiveStateMarkers.contains {
            text.localizedCaseInsensitiveContains($0)
        }
        if looksLikeQuestion && !alsoStatesAnExperience {
            return SubjectiveCaptureDecision(
                shouldPersist: false,
                reason: .ordinaryQuestion,
                topicKey: "ask.question"
            )
        }

        if alsoStatesAnExperience
            || selfReportMarkers.contains(where: { text.localizedCaseInsensitiveContains($0) }) {
            return SubjectiveCaptureDecision(
                shouldPersist: true,
                reason: .explicitSelfReport,
                topicKey: "ask.self_report"
            )
        }

        return SubjectiveCaptureDecision(
            shouldPersist: false,
            reason: .ordinaryQuestion,
            topicKey: "ask.question"
        )
    }
}

@MainActor
enum SubjectiveEventWriter {
    @discardableResult
    static func saveIfEligible(
        text: String,
        origin: SubjectiveInputOrigin,
        modelContext: ModelContext,
        occurredAt: Date = Date()
    ) -> TimelineRecord? {
        let decision = SubjectiveInputClassifier.classify(text, origin: origin)
        guard decision.shouldPersist else { return nil }

        let source: String
        let eventType: String
        switch origin {
        case .ask:
            source = TimelineRecordSource.ask
            eventType = TimelineRecordType.askStatement
        case .onboarding:
            source = TimelineRecordSource.onboarding
            eventType = TimelineRecordType.onboardingAnswer
        }

        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let record = TimelineRecord(
            createdAt: occurredAt,
            eventType: eventType,
            rawTranscript: cleanText,
            confirmedText: cleanText,
            tags: [],
            recordingDuration: 0,
            source: source,
            saveStatus: TimelineRecordStatus.saved,
            topicKey: decision.topicKey,
            confirmationStatus: .confirmed,
            extractionStatus: .pending
        )
        modelContext.insert(record)
        do {
            try modelContext.save()
            return record
        } catch {
            modelContext.delete(record)
            return nil
        }
    }
}

/// One-way compatibility bridge for the previously disconnected HealthDataStore note table.
/// TimelineRecord becomes authoritative so migrated notes gain the same edit/hide/delete behavior.
@MainActor
enum SubjectiveLegacyMigrator {
    static let migrationKey = "subjective_legacy_health_store_migration_v1"

    @discardableResult
    static func migrateIfNeeded(
        notes: [SubjectiveNote],
        existingRecords: [TimelineRecord],
        modelContext: ModelContext,
        defaults: UserDefaults = .standard
    ) -> [TimelineRecord] {
        guard !defaults.bool(forKey: migrationKey) else { return [] }

        var inserted: [TimelineRecord] = []
        for note in notes {
            let alreadyExists = (existingRecords + inserted).contains { record in
                record.eventType == TimelineRecordType.legacySubjectiveNote
                    && record.createdAt == note.date
                    && record.confirmedText == note.text
                    && record.subjectiveMetadata.topicKey == note.topicKey
            }
            guard !alreadyExists else { continue }

            let record = TimelineRecord(
                createdAt: note.date,
                eventType: TimelineRecordType.legacySubjectiveNote,
                rawTranscript: note.rawText,
                confirmedText: note.text,
                tags: [],
                recordingDuration: 0,
                source: TimelineRecordSource.legacySubjectiveStore,
                saveStatus: TimelineRecordStatus.saved,
                topicKey: note.topicKey,
                confirmationStatus: note.confirmationStatus,
                extractionStatus: .pending,
                timezoneIdentifier: note.timezoneIdentifier
            )
            modelContext.insert(record)
            inserted.append(record)
        }

        do {
            try modelContext.save()
            defaults.set(true, forKey: migrationKey)
            return inserted
        } catch {
            inserted.forEach(modelContext.delete)
            return []
        }
    }
}
