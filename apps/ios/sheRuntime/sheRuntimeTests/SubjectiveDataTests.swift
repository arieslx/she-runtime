import Foundation
import SwiftData
import Testing
@testable import sheRuntime

@MainActor
struct SubjectiveDataContractTests {
    @Test func legacyMockTagsBecomePendingInsteadOfFacts() throws {
        let payload = try JSONEncoder().encode(SubjectiveRecordMetadata.legacyMockTags)
        let metadata = SubjectiveRecordMetadata.decode(payload, fallbackDate: Date(timeIntervalSince1970: 0))

        #expect(metadata.schemaVersion == 0)
        #expect(metadata.extractionStatus == .pending)
        #expect(metadata.annotations.isEmpty)
    }

    @Test func editingSourceTextInvalidatesDerivedAnnotations() throws {
        let record = makeRecord(text: "下午很累")
        var metadata = SubjectiveRecordMetadata.pending(
            topicKey: "energy",
            confirmationStatus: .confirmed,
            updatedAt: record.createdAt
        )
        metadata.extractionStatus = .completed
        metadata.extractionVersion = "extractor-v1"
        metadata.extractionConfidence = 0.91
        metadata.annotations = [
            SubjectiveAnnotation(
                id: "annotation-1",
                kind: .tag,
                dimension: .bodySensation,
                value: "疲劳",
                confidence: 0.91,
                extractorVersion: "extractor-v1",
                confirmationStatus: .userConfirmed
            )
        ]
        record.tagsData = try JSONEncoder().encode(metadata)

        record.updateConfirmedText("下午只是有点困")

        #expect(record.confirmedText == "下午只是有点困")
        #expect(record.subjectiveMetadata.revision == 2)
        #expect(record.subjectiveMetadata.confirmationStatus == .corrected)
        #expect(record.subjectiveMetadata.extractionStatus == .pending)
        #expect(record.subjectiveMetadata.extractionVersion == nil)
        #expect(record.subjectiveMetadata.annotations.isEmpty)
    }

    @Test func askCaptureRuleSeparatesSelfReportsFromOrdinaryQuestions() {
        let onboarding = SubjectiveInputClassifier.classify(
            "通常一点以后睡",
            origin: .onboarding(promptKey: "onboarding.q.sleep_onset")
        )
        let report = SubjectiveInputClassifier.classify("我昨晚没睡好，今天很累", origin: .ask)
        let ellipticalReport = SubjectiveInputClassifier.classify("最近总是头疼", origin: .ask)
        let hypothesis = SubjectiveInputClassifier.classify("我怀疑是连续开会后更累", origin: .ask)
        let question = SubjectiveInputClassifier.classify("我昨晚睡得怎么样？", origin: .ask)
        let generalQuestion = SubjectiveInputClassifier.classify("什么是头疼？", origin: .ask)

        #expect(onboarding.shouldPersist)
        #expect(report.reason == .explicitSelfReport)
        #expect(ellipticalReport.reason == .explicitSelfReport)
        #expect(hypothesis.reason == .personalHypothesis)
        #expect(!question.shouldPersist)
        #expect(question.reason == .ordinaryQuestion)
        #expect(!generalQuestion.shouldPersist)
    }

    @Test func unreviewedTranscriptIsReadableButNotUsedAsEvidence() {
        let record = makeRecord(text: "自动转写还没确认", confirmationStatus: .unreviewed)

        #expect(SubjectiveEventAdapter.activeEvents(from: [record]).count == 1)
        #expect(SubjectiveEventAdapter.notes(from: [record]).isEmpty)
    }

    @Test func hiddenAndDeletedRecordsLeaveEveryDownstreamSnapshot() throws {
        let container = try memoryContainer()
        let context = ModelContext(container)
        let record = makeRecord(text: "今天头疼")
        context.insert(record)
        try context.save()
        #expect(SubjectiveEventAdapter.activeEvents(from: [record]).count == 1)

        record.isHidden = true
        try context.save()
        #expect(SubjectiveEventAdapter.activeEvents(from: [record]).isEmpty)

        context.delete(record)
        try context.save()
        let remaining = try context.fetch(FetchDescriptor<TimelineRecord>())
        #expect(SubjectiveEventAdapter.activeEvents(from: remaining).isEmpty)
    }

    @Test func disconnectedLegacyNotesMigrateIntoEditableTimelineOnce() throws {
        let container = try memoryContainer()
        let context = ModelContext(container)
        let suiteName = "SubjectiveLegacyMigratorTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let note = SubjectiveNote(
            date: Date(timeIntervalSince1970: 1_777_000_000),
            topicKey: "legacy.sleep",
            text: "以前常常睡不着"
        )

        let inserted = SubjectiveLegacyMigrator.migrateIfNeeded(
            notes: [note],
            existingRecords: [],
            modelContext: context,
            defaults: defaults
        )
        let secondPass = SubjectiveLegacyMigrator.migrateIfNeeded(
            notes: [note],
            existingRecords: inserted,
            modelContext: context,
            defaults: defaults
        )

        let record = try #require(inserted.first)
        #expect(secondPass.isEmpty)
        #expect(record.eventType == TimelineRecordType.legacySubjectiveNote)
        #expect(record.source == TimelineRecordSource.legacySubjectiveStore)
        #expect(record.subjectiveMetadata.topicKey == "legacy.sleep")
        #expect(SubjectiveEventAdapter.activeEvents(from: inserted).first?.confirmedText == note.text)
    }

    @Test func recordSurvivesPersistentContainerReopen() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SubjectivePersistence-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("timeline.store")
        let recordID = UUID()

        do {
            let container = try persistentContainer(url: storeURL)
            let context = ModelContext(container)
            context.insert(makeRecord(id: recordID, text: "重启以后也要记得"))
            try context.save()
        }

        do {
            let reopened = try persistentContainer(url: storeURL)
            let context = ModelContext(reopened)
            let records = try context.fetch(FetchDescriptor<TimelineRecord>())
            let event = try #require(SubjectiveEventAdapter.activeEvents(from: records).first)
            #expect(event.id == recordID)
            #expect(event.confirmedText == "重启以后也要记得")
            #expect(event.extractionStatus == .pending)
        }
    }

    @Test func persistedSelfReportReachesAskAndEvidenceThenRevocationRemovesIt() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SubjectiveVerticalSlice-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("timeline.store")
        let occurredAt = Date(timeIntervalSince1970: 1_777_000_000)
        var savedID = ""

        do {
            let container = try persistentContainer(url: storeURL)
            let context = ModelContext(container)
            let record = try #require(SubjectiveEventWriter.saveIfEligible(
                text: "我昨晚没睡好，今天很累",
                origin: .ask,
                modelContext: context,
                occurredAt: occurredAt
            ))
            savedID = record.id.uuidString
        }

        let reopened = try persistentContainer(url: storeURL)
        let context = ModelContext(reopened)
        let records = try context.fetch(FetchDescriptor<TimelineRecord>())
        let events = SubjectiveEventAdapter.activeEvents(from: records)
        let daily = DailyRecord(
            date: occurredAt,
            sleepHours: 5.8,
            sleepOnsetMinutes: nil,
            hrv: 43,
            restingHeartRate: nil,
            wristTemp: nil,
            respiratoryRate: nil,
            steps: nil,
            hasMenses: false,
            headphoneHours: nil,
            daylightMinutes: nil,
            mindfulMinutes: nil
        )
        let askContext = await LocalAskContextProvider(dailyProvider: { [daily] })
            .makeContext(subjectiveEvents: events, now: occurredAt.addingTimeInterval(60))
        let evidence = EvidenceEngine().compute(
            daily: [daily],
            hourly: [],
            notes: SubjectiveEventAdapter.notes(from: records)
        )

        #expect(askContext.subjectiveEvents.first?.sourceEventID == savedID)
        #expect(evidence.subjectiveAlignments.first?.sourceEventID == savedID)
        #expect(evidence.subjectiveAlignments.first?.claim == .cooccurrence)

        let persistedRecord = try #require(records.first)
        persistedRecord.isHidden = true
        try context.save()
        let activeAfterRevocation = SubjectiveEventAdapter.activeEvents(from: records)
        let askAfterRevocation = await LocalAskContextProvider(dailyProvider: { [daily] })
            .makeContext(subjectiveEvents: activeAfterRevocation, now: occurredAt.addingTimeInterval(60))
        let evidenceAfterRevocation = EvidenceEngine().compute(
            daily: [daily],
            hourly: [],
            notes: SubjectiveEventAdapter.notes(from: records)
        )

        #expect(askAfterRevocation.subjectiveEvents.isEmpty)
        #expect(evidenceAfterRevocation.subjectiveAlignments.isEmpty)
    }

    private func makeRecord(
        id: UUID = UUID(),
        text: String,
        confirmationStatus: SubjectiveConfirmationStatus = .confirmed
    ) -> TimelineRecord {
        TimelineRecord(
            id: id,
            createdAt: Date(timeIntervalSince1970: 1_777_000_000),
            eventType: TimelineRecordType.voiceCheckIn,
            rawTranscript: text,
            confirmedText: text,
            tags: [],
            recordingDuration: 3,
            source: TimelineRecordSource.iPhoneVoice,
            saveStatus: TimelineRecordStatus.saved,
            confirmationStatus: confirmationStatus,
            extractionStatus: .pending
        )
    }

    private func memoryContainer() throws -> ModelContainer {
        let schema = Schema([TimelineRecord.self])
        let configuration = ModelConfiguration(
            "SubjectiveDataTests",
            schema: schema,
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func persistentContainer(url: URL) throws -> ModelContainer {
        let schema = Schema([TimelineRecord.self])
        let configuration = ModelConfiguration(
            "SubjectivePersistenceTests",
            schema: schema,
            url: url,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

@MainActor
struct SubjectiveEvidenceAlignmentTests {
    @Test func sameDayJoinIsCooccurrenceAndNeverCreatesAOneNotePattern() throws {
        let date = Date(timeIntervalSince1970: 1_777_000_000)
        let daily = [dailyRecord(date: date, sleepHours: 6.2, hrv: 42)]
        let note = SubjectiveNote(
            date: date.addingTimeInterval(3_600),
            topicKey: "ask.self_report",
            text: "今天下午很累",
            id: "event-1",
            source: SubjectiveEventSource.ask.rawValue,
            timezoneIdentifier: "Asia/Shanghai",
            extractionStatus: .pending,
            confirmationStatus: .confirmed,
            revision: 1
        )
        let engine = EvidenceEngine()
        let objectiveOnly = engine.compute(daily: daily, hourly: [], notes: [])
        let result = engine.compute(daily: daily, hourly: [], notes: [note])
        let alignment = try #require(result.subjectiveAlignments.first)

        #expect(alignment.claim == .cooccurrence)
        #expect(alignment.sourceEventID == "event-1")
        #expect(alignment.objectiveFacts.contains { $0.metricKey == "sleep_hours" && $0.value == 6.2 })
        #expect(result.insights.map(\.id) == objectiveOnly.insights.map(\.id))
    }

    @Test func noObjectiveWindowStaysFactOnlyAndDeletionRemovesIt() throws {
        let note = SubjectiveNote(
            date: Date(timeIntervalSince1970: 1_777_000_000),
            topicKey: "voice.free_expression",
            text: "今天心情有点低",
            id: "event-2",
            source: SubjectiveEventSource.iPhoneVoice.rawValue,
            extractionStatus: .pending,
            confirmationStatus: .confirmed
        )
        let engine = EvidenceEngine()
        let withNote = engine.compute(daily: [], hourly: [], notes: [note])
        let afterDeletion = engine.compute(daily: [], hourly: [], notes: [])

        #expect(withNote.subjectiveAlignments.first?.claim == .factOnly)
        #expect(withNote.insights.isEmpty)
        #expect(afterDeletion.subjectiveAlignments.isEmpty)
        #expect(!afterDeletion.hasAnyData)
    }

    private func dailyRecord(date: Date, sleepHours: Double?, hrv: Double?) -> DailyRecord {
        DailyRecord(
            date: date,
            sleepHours: sleepHours,
            sleepOnsetMinutes: nil,
            hrv: hrv,
            restingHeartRate: nil,
            wristTemp: nil,
            respiratoryRate: nil,
            steps: nil,
            hasMenses: false,
            headphoneHours: nil,
            daylightMinutes: nil,
            mindfulMinutes: nil
        )
    }
}

@MainActor
struct AskCompactContextTests {
    @Test func contextIsBoundedTraceableAndExcludesRawTranscript() async throws {
        let now = Date(timeIntervalSince1970: 1_777_000_000)
        let daily = DailyRecord(
            date: now.addingTimeInterval(-3_600),
            sleepHours: 7.5,
            sleepOnsetMinutes: 45,
            hrv: 51,
            restingHeartRate: 59,
            wristTemp: nil,
            respiratoryRate: nil,
            steps: 8_200,
            hasMenses: false,
            headphoneHours: nil,
            daylightMinutes: 35,
            mindfulMinutes: nil
        )
        let provider = LocalAskContextProvider(dailyProvider: { [daily] })
        let events = (0..<13).map { index in
            SubjectiveEvent(
                id: UUID(),
                occurredAt: now.addingTimeInterval(TimeInterval(-index * 60)),
                timezoneIdentifier: "Asia/Shanghai",
                source: .ask,
                topicKey: "ask.self_report",
                rawText: "RAW_SHOULD_STAY_LOCAL_\(index)",
                confirmedText: String(repeating: "困", count: 260),
                extractionStatus: .pending,
                extractionVersion: nil,
                extractionConfidence: nil,
                confirmationStatus: .confirmed,
                revision: 1,
                annotations: []
            )
        }

        let context = await provider.makeContext(subjectiveEvents: events, now: now)
        let request = AskChatRequest(
            message: "我最近为什么总困？",
            locale: "zh-CN",
            timezone: "Asia/Shanghai",
            context: context
        )
        let encoded = try JSONEncoder().encode(request)
        let json = try #require(String(data: encoded, encoding: .utf8))

        #expect(context.subjectiveEvents.count == 12)
        #expect(context.subjectiveEvents.first?.confirmedText.count == 240)
        #expect(context.healthSummary.effectiveDayCount == 1)
        #expect(context.healthSummary.metrics.contains { $0.metricKey == "hrv" && $0.latestValue == 51 })
        #expect(json.contains("source_event_id"))
        #expect(json.contains("health_summary"))
        #expect(!json.contains("RAW_SHOULD_STAY_LOCAL"))
    }

    @Test func unreviewedEventsStayOnDeviceUntilConfirmed() async {
        let now = Date(timeIntervalSince1970: 1_777_000_000)
        let provider = LocalAskContextProvider(dailyProvider: { [] })
        let event = SubjectiveEvent(
            id: UUID(),
            occurredAt: now,
            timezoneIdentifier: "Asia/Shanghai",
            source: .stopWatchVoice,
            topicKey: "voice.free_expression",
            rawText: "raw",
            confirmedText: "自动转写",
            extractionStatus: .pending,
            extractionVersion: nil,
            extractionConfidence: nil,
            confirmationStatus: .unreviewed,
            revision: 1,
            annotations: []
        )

        let context = await provider.makeContext(subjectiveEvents: [event], now: now)

        #expect(context.subjectiveEvents.isEmpty)
    }
}
