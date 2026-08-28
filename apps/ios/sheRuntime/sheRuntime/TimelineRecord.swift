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

    init(
        id: UUID = UUID(),
        createdAt: Date,
        eventType: String,
        rawTranscript: String,
        confirmedText: String,
        tags: [String],
        recordingDuration: TimeInterval,
        source: String,
        saveStatus: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.eventType = eventType
        self.rawTranscript = rawTranscript
        self.confirmedText = confirmedText
        self.tagsData = (try? JSONEncoder().encode(tags)) ?? Data()
        self.recordingDuration = recordingDuration
        self.source = source
        self.saveStatus = saveStatus
    }

    var tags: [String] {
        (try? JSONDecoder().decode([String].self, from: tagsData)) ?? []
    }
}

enum TimelineRecordType {
    static let voiceCheckIn = "Voice check-in"
}

enum TimelineRecordSource {
    static let iPhoneVoice = "iPhone voice"
    static let stopWatch = "sheRuntime StopWatch"
}

enum TimelineRecordStatus {
    static let saved = "saved"
}
