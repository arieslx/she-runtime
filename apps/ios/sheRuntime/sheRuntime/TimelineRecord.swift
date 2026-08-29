import Foundation
import SwiftData

@Model
final class TimelineRecord {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var eventType: String
    var rawTranscript: String
    var confirmedText: String
    var tagsData: Data
    var recordingDuration: TimeInterval
    var source: String
    var saveStatus: String
    var isHidden: Bool = false

    init(
        id: UUID = UUID(),
        createdAt: Date,
        eventType: String,
        rawTranscript: String,
        confirmedText: String,
        tags: [String],
        recordingDuration: TimeInterval,
        source: String,
        saveStatus: String,
        isHidden: Bool = false,
        topicKey: String = "voice.free_expression",
        confirmationStatus: SubjectiveConfirmationStatus = .confirmed,
        extractionStatus: SubjectiveExtractionStatus = .pending,
        timezoneIdentifier: String? = TimeZone.current.identifier
    ) {
        self.id = id
        self.createdAt = createdAt
        self.eventType = eventType
        self.rawTranscript = rawTranscript
        self.confirmedText = confirmedText
        var metadata = SubjectiveRecordMetadata.pending(
            topicKey: topicKey,
            timezoneIdentifier: timezoneIdentifier,
            confirmationStatus: confirmationStatus,
            updatedAt: createdAt
        )
        metadata.extractionStatus = extractionStatus
        if !tags.isEmpty {
            // Callers must opt into a completed extraction before these can be used as facts.
            metadata.annotations = tags.enumerated().map { index, value in
                SubjectiveAnnotation(
                    id: "initial-\(index)",
                    kind: .tag,
                    dimension: .unknown,
                    value: value,
                    confidence: nil,
                    extractorVersion: nil,
                    confirmationStatus: .pending
                )
            }
        }
        self.tagsData = (try? JSONEncoder().encode(metadata)) ?? Data()
        self.recordingDuration = recordingDuration
        self.source = source
        self.saveStatus = saveStatus
        self.isHidden = isHidden
    }

    var tags: [String] {
        subjectiveMetadata.annotations.map(\.value)
    }

    var subjectiveMetadata: SubjectiveRecordMetadata {
        SubjectiveRecordMetadata.decode(tagsData, fallbackDate: createdAt)
    }

    /// Editing source text invalidates every annotation derived from the previous wording.
    func updateConfirmedText(_ value: String, updatedAt: Date = Date()) {
        confirmedText = value
        var metadata = subjectiveMetadata
        metadata.revision += 1
        metadata.updatedAt = updatedAt
        metadata.confirmationStatus = .corrected
        metadata.extractionStatus = .pending
        metadata.extractionVersion = nil
        metadata.extractionConfidence = nil
        metadata.annotations = []
        tagsData = (try? JSONEncoder().encode(metadata)) ?? Data()
    }
}

enum TimelineRecordType {
    static let voiceCheckIn = "Voice check-in"
    static let askStatement = "Ask self-report"
    static let onboardingAnswer = "Onboarding answer"
    static let legacySubjectiveNote = "Legacy subjective note"

    static let subjectiveTypes: Set<String> = [
        voiceCheckIn,
        askStatement,
        onboardingAnswer,
        legacySubjectiveNote
    ]
}

enum TimelineRecordSource {
    static let iPhoneVoice = "iPhone voice"
    static let stopWatch = "sheRuntime StopWatch"
    static let ask = "Ask"
    static let onboarding = "Onboarding"
    static let legacySubjectiveStore = "Legacy subjective store"
}

enum TimelineRecordStatus {
    static let saved = "saved"
}
