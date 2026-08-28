import Foundation

struct AskChatConfig {
    static let local = AskChatConfig(
        endpoint: URL(string: "http://192.168.104.28:3000/api/ask")!,
        timeout: 12
    )

    let endpoint: URL
    let timeout: TimeInterval
}

protocol AskChatClient {
    func ask(_ request: AskChatRequest) async throws -> AskChatResponse
}

struct AskChatRequest: Encodable {
    let message: String
    let locale: String
    let timezone: String
}

struct RemoteAskChatClient: AskChatClient {
    private let config: AskChatConfig
    private let session: URLSession

    init(config: AskChatConfig = .local, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    func ask(_ request: AskChatRequest) async throws -> AskChatResponse {
        var urlRequest = URLRequest(url: config.endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = config.timeout
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw AskChatClientError.badResponse
        }

        return try JSONDecoder().decode(AskChatResponse.self, from: data)
    }
}

enum AskChatClientError: Error {
    case badResponse
}
