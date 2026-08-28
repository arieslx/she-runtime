import Combine
import Foundation

@MainActor
final class AskChatViewModel: ObservableObject {
    @Published private(set) var activeExchange: AskChatExchange?
    @Published private(set) var isResponding = false
    @Published private(set) var serviceStatus: AskServiceStatus = .idle

    private let client: AskChatClient
    private var responseTask: Task<Void, Never>?
    private var healthTask: Task<Void, Never>?

    init(client: AskChatClient? = nil) {
        self.client = client ?? RemoteAskChatClient()
    }

    var endpointDescription: String {
        client.endpointDescription
    }

    var healthEndpointDescription: String {
        client.healthEndpointDescription ?? C.t("ask.healthEndpointUnavailable")
    }

    func checkHealth() {
        healthTask?.cancel()
        serviceStatus = .checking

        healthTask = Task { [weak self] in
            guard !Task.isCancelled, let self else { return }
            do {
                let health = try await client.checkHealth()
                guard !Task.isCancelled else { return }
                serviceStatus = health.ok ? .healthy(health) : .unhealthy(C.t("ask.healthNotOk"))
            } catch {
                guard !Task.isCancelled else { return }
                serviceStatus = .unhealthy(Self.describe(error))
            }
        }
    }

    func send(_ rawMessage: String) {
        let message = rawMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }

        responseTask?.cancel()
        isResponding = true
        activeExchange = AskChatExchange(question: message, response: nil, errorMessage: nil)

        responseTask = Task { [weak self] in
            guard !Task.isCancelled, let self else { return }
            do {
                let response = try await client.ask(
                    AskChatRequest(
                        message: message,
                        locale: AppLanguage.current == .en ? "en-US" : "zh-CN",
                        timezone: TimeZone.current.identifier
                    )
                )
                guard !Task.isCancelled else { return }
                activeExchange = AskChatExchange(question: message, response: response, errorMessage: nil)
            } catch {
                guard !Task.isCancelled else { return }
                activeExchange = AskChatExchange(
                    question: message,
                    response: nil,
                    errorMessage: Self.describe(error)
                )
            }
            isResponding = false
        }
    }

    private static func describe(_ error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty {
            return description
        }
        return error.localizedDescription
    }
}

struct AskChatExchange: Equatable {
    let question: String
    let response: AskChatResponse?
    let errorMessage: String?

    init(question: String, response: AskChatResponse?, errorMessage: String? = nil) {
        self.question = question
        self.response = response
        self.errorMessage = errorMessage
    }
}

enum AskServiceStatus: Equatable {
    case idle
    case checking
    case healthy(AskServiceHealth)
    case unhealthy(String)
}

struct AskChatResponse: Codable, Equatable {
    let answer: String
    let basis: [AskChatBasis]
    let safetyNote: String?
    let followUp: String?
    let usage: AskChatUsage?
    let sources: [AskChatSource]

    init(
        answer: String,
        basis: [AskChatBasis],
        safetyNote: String? = nil,
        followUp: String? = nil,
        usage: AskChatUsage? = nil,
        sources: [AskChatSource] = []
    ) {
        self.answer = answer
        self.basis = basis
        self.safetyNote = safetyNote
        self.followUp = followUp
        self.usage = usage
        self.sources = sources
    }

    enum CodingKeys: String, CodingKey {
        case answer
        case basis
        case safetyNote = "safety_note"
        case followUp = "follow_up"
        case usage
        case sources
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        answer = try container.decode(String.self, forKey: .answer)
        basis = try container.decodeIfPresent([AskChatBasis].self, forKey: .basis) ?? []
        safetyNote = try container.decodeIfPresent(String.self, forKey: .safetyNote)
        followUp = try container.decodeIfPresent(String.self, forKey: .followUp)
        usage = try container.decodeIfPresent(AskChatUsage.self, forKey: .usage)
        sources = try container.decodeIfPresent([AskChatSource].self, forKey: .sources) ?? []
    }
}

struct AskChatBasis: Identifiable, Codable, Equatable {
    var id: String { "\(label)-\(value)" }
    let label: String
    let value: String
}

struct AskChatUsage: Codable, Equatable {
    let deepSeekCallCount: Int

    enum CodingKeys: String, CodingKey {
        case deepSeekCallCount = "deepseek_call_count"
    }
}

struct AskChatSource: Identifiable, Codable, Equatable {
    let sourceID: String
    let sourceType: String
    let label: String
    let path: String
    let url: String
    let status: String
    let detail: String

    var id: String {
        [sourceType, sourceID, label, path, url].joined(separator: "|")
    }

    enum CodingKeys: String, CodingKey {
        case sourceID = "source_id"
        case sourceType = "source_type"
        case label
        case path
        case url
        case status
        case detail
    }

    init(
        sourceID: String,
        sourceType: String,
        label: String,
        path: String = "",
        url: String = "",
        status: String = "",
        detail: String = ""
    ) {
        self.sourceID = sourceID
        self.sourceType = sourceType
        self.label = label
        self.path = path
        self.url = url
        self.status = status
        self.detail = detail
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourceID = try container.decodeIfPresent(String.self, forKey: .sourceID) ?? ""
        sourceType = try container.decodeIfPresent(String.self, forKey: .sourceType) ?? ""
        label = try container.decodeIfPresent(String.self, forKey: .label) ?? ""
        path = try container.decodeIfPresent(String.self, forKey: .path) ?? ""
        url = try container.decodeIfPresent(String.self, forKey: .url) ?? ""
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? ""
        detail = try container.decodeIfPresent(String.self, forKey: .detail) ?? ""
    }
}
