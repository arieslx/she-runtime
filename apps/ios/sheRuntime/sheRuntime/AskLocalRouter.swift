import Foundation
import SwiftData

protocol AskHealthDataProviding: Sendable {
    func loadTodaySteps(now: Date) async throws -> Int?
    func loadLatestPrimarySleep(now: Date, calendar: Calendar) async throws -> SleepSummary?
}

extension HealthKitManager: AskHealthDataProviding {}

@MainActor
struct AskLocalRouter {
    private let health: any AskHealthDataProviding
    private let calendar: Calendar
    private let knowledge: AskBundledKnowledgeStore

    init(health: (any AskHealthDataProviding)? = nil, calendar: Calendar = .current, knowledge: AskBundledKnowledgeStore? = nil) {
        self.health = health ?? HealthKitManager.shared
        self.calendar = calendar
        self.knowledge = knowledge ?? AskBundledKnowledgeStore()
    }

    func answerIfPossible(message: String, modelContext: ModelContext, now: Date = Date()) async -> AskChatResponse? {
        let normalized = message.lowercased()
        if Self.matches(normalized, any: ["今天走了多少步", "今天多少步", "today's steps", "steps today"]) {
            guard let steps = try? await health.loadTodaySteps(now: now) else { return nil }
            return localResponse(answer: String(format: C.t("ask.localStepsAnswer"), steps), sourceID: "HEALTHKIT-STEPS")
        }
        if Self.matches(normalized, any: ["昨晚睡了多久", "昨晚睡眠多久", "last night's sleep", "sleep last night"]) {
            guard let sleep = try? await health.loadLatestPrimarySleep(now: now, calendar: calendar) else { return nil }
            return localResponse(answer: String(format: C.t("ask.localSleepAnswer"), sleep.totalSleepDuration / 3600), sourceID: "HEALTHKIT-SLEEP")
        }
        if Self.matches(normalized, any: ["今天记录过几次", "今天记录了几次", "今天有几条记录", "records today"]) {
            let start = calendar.startOfDay(for: now)
            let predicate = #Predicate<TimelineRecord> { record in
                record.createdAt >= start && record.createdAt <= now && !record.isHidden
            }
            guard let count = try? modelContext.fetchCount(FetchDescriptor(predicate: predicate)) else { return nil }
            return localResponse(answer: String(format: C.t("ask.localRecordCountAnswer"), count), sourceID: "SWIFTDATA-TIMELINE")
        }
        if Self.matches(normalized, any: ["最近一条记录", "最后一条记录", "latest record", "last record"]) {
            let predicate = #Predicate<TimelineRecord> { !$0.isHidden }
            var descriptor = FetchDescriptor<TimelineRecord>(predicate: predicate, sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
            descriptor.fetchLimit = 1
            guard let record = try? modelContext.fetch(descriptor).first else { return nil }
            return localResponse(answer: String(format: C.t("ask.localLatestRecordAnswer"), record.confirmedText), sourceID: "SWIFTDATA-TIMELINE")
        }
        if let item = knowledge.answer(for: normalized) {
            return AskChatResponse(
                requestID: UUID().uuidString,
                answer: item.answer,
                basis: [],
                safetyNote: C.t("ask.localKnowledgeSafety"),
                usage: AskChatUsage(deepSeekCallCount: 0),
                sources: [AskChatSource(sourceID: item.sourceID, sourceType: "local_knowledge", label: C.t("ask.localKnowledgeSource"))],
                route: AskChatRoute(localDBUsed: false, localKnowledgeUsed: true, onlineToolCalled: false, llmCalled: false)
            )
        }
        return nil
    }

    private func localResponse(answer: String, sourceID: String) -> AskChatResponse {
        AskChatResponse(
            requestID: UUID().uuidString,
            answer: answer,
            basis: [],
            safetyNote: C.t("ask.localAnswerSafety"),
            usage: AskChatUsage(deepSeekCallCount: 0),
            sources: [AskChatSource(sourceID: sourceID, sourceType: "local_db", label: C.t("ask.localDataSource"))],
            route: AskChatRoute(localDBUsed: true, localKnowledgeUsed: false, onlineToolCalled: false, llmCalled: false)
        )
    }

    private static func matches(_ message: String, any phrases: [String]) -> Bool {
        phrases.contains { message.contains($0) }
    }
}
