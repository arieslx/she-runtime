import Combine
import Foundation

@MainActor
final class AskChatViewModel: ObservableObject {
    @Published private(set) var activeExchange: AskChatExchange?
    @Published private(set) var isResponding = false

    private let client: AskChatClient
    private var responseTask: Task<Void, Never>?

    init(client: AskChatClient? = nil) {
        self.client = client ?? RemoteAskChatClient()
    }

    func send(_ rawMessage: String) {
        let message = rawMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }

        responseTask?.cancel()
        isResponding = true
        activeExchange = AskChatExchange(question: message, response: nil)

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
                activeExchange = AskChatExchange(question: message, response: response)
            } catch {
                activeExchange = AskMock.makeChatExchange(question: message)
            }
            isResponding = false
        }
    }
}

struct AskChatExchange: Equatable {
    let question: String
    let response: AskChatResponse?
}

struct AskChatResponse: Codable, Equatable {
    let answer: String
    let basis: [AskChatBasis]
    let safetyNote: String?
    let followUp: String?
    let usage: AskChatUsage?

    init(
        answer: String,
        basis: [AskChatBasis],
        safetyNote: String? = nil,
        followUp: String? = nil,
        usage: AskChatUsage? = nil
    ) {
        self.answer = answer
        self.basis = basis
        self.safetyNote = safetyNote
        self.followUp = followUp
        self.usage = usage
    }

    enum CodingKeys: String, CodingKey {
        case answer
        case basis
        case safetyNote = "safety_note"
        case followUp = "follow_up"
        case usage
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
