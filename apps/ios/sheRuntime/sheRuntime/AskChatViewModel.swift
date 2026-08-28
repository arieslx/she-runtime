import Combine
import Foundation

@MainActor
final class AskChatViewModel: ObservableObject {
    @Published private(set) var activeExchange: AskChatExchange?
    @Published private(set) var isResponding = false

    private var responseTask: Task<Void, Never>?

    func send(_ rawMessage: String) {
        let message = rawMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }

        responseTask?.cancel()
        isResponding = true
        activeExchange = AskChatExchange(question: message, response: nil)

        responseTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled, let self else { return }
            activeExchange = AskMock.makeChatExchange(question: message)
            isResponding = false
        }
    }
}

struct AskChatExchange: Equatable {
    let question: String
    let response: AskChatResponse?
}

struct AskChatResponse: Equatable {
    let answer: String
    let basis: [AskChatBasis]
}

struct AskChatBasis: Identifiable, Equatable {
    let id = UUID()
    let label: String
    let value: String
}
