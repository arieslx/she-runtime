import Foundation
import SwiftData

struct AskCompactContext: Codable, Equatable {
    let today: AskTodayContext?
    let recentRecords: [AskRecentRecord]
    let matchedPatterns: [AskMatchedPattern]
    let localKnowledge: [AskLocalKnowledgeItem]

    enum CodingKeys: String, CodingKey {
        case today
        case recentRecords = "recent_records"
        case matchedPatterns = "matched_patterns"
        case localKnowledge = "local_knowledge"
    }

    static let empty = AskCompactContext(
        today: nil,
        recentRecords: [],
        matchedPatterns: [],
        localKnowledge: []
    )
}

struct AskTodayContext: Codable, Equatable {
    let date: String
    let recordCount: Int

    enum CodingKeys: String, CodingKey {
        case date
        case recordCount = "record_count"
    }
}

struct AskRecentRecord: Codable, Equatable {
    let createdAt: String
    let eventType: String
    let text: String
    let tags: [String]

    enum CodingKeys: String, CodingKey {
        case createdAt = "created_at"
        case eventType = "event_type"
        case text
        case tags
    }
}

struct AskMatchedPattern: Codable, Equatable {
    let patternID: String
    let summary: String

    enum CodingKeys: String, CodingKey {
        case patternID = "pattern_id"
        case summary
    }
}

struct AskLocalKnowledgeItem: Codable, Equatable {
    let sourceID: String
    let title: String
    let snippet: String

    enum CodingKeys: String, CodingKey {
        case sourceID = "source_id"
        case title
        case snippet
    }
}

@MainActor
struct AskLocalContextProvider {
    static let maximumRecords = 8
    static let maximumTextLength = 240
    static let maximumTags = 6
    static let maximumTagLength = 32

    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func makeContext(message: String, modelContext: ModelContext, now: Date = Date()) throws -> AskCompactContext {
        guard Self.requestsPersonalContext(message) else { return .empty }

        let startDate = Self.requestsToday(message)
            ? calendar.startOfDay(for: now)
            : calendar.date(byAdding: .day, value: -7, to: now) ?? now
        let predicate = #Predicate<TimelineRecord> { record in
            record.createdAt >= startDate && record.createdAt <= now && !record.isHidden
        }
        var descriptor = FetchDescriptor<TimelineRecord>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = Self.maximumRecords
        let records = try modelContext.fetch(descriptor)
        guard !records.isEmpty else { return .empty }

        let formatter = ISO8601DateFormatter()
        let compactRecords = records.map { record in
            AskRecentRecord(
                createdAt: formatter.string(from: record.createdAt),
                eventType: Self.truncate(record.eventType, to: 64),
                text: Self.truncate(record.confirmedText, to: Self.maximumTextLength),
                tags: record.tags.prefix(Self.maximumTags).map {
                    Self.truncate($0, to: Self.maximumTagLength)
                }
            )
        }
        let todayCount = records.filter { calendar.isDate($0.createdAt, inSameDayAs: now) }.count
        let today = todayCount > 0
            ? AskTodayContext(date: Self.dayString(now, calendar: calendar), recordCount: todayCount)
            : nil

        return AskCompactContext(
            today: today,
            recentRecords: compactRecords,
            matchedPatterns: [],
            localKnowledge: []
        )
    }

    static func requestsPersonalContext(_ message: String) -> Bool {
        let normalized = message.lowercased()
        return ["我", "我的", "今天", "昨晚", "昨天", "最近", "刚才", "记录", "today", "my ", "recent", "last night"]
            .contains { normalized.contains($0) }
    }

    private static func requestsToday(_ message: String) -> Bool {
        let normalized = message.lowercased()
        return normalized.contains("今天") || normalized.contains("today") || normalized.contains("刚才")
    }

    private static func truncate(_ value: String, to limit: Int) -> String {
        String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
    }

    private static func dayString(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}
