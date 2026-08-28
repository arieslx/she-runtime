import Foundation

struct AskChatConfig {
    static var local: AskChatConfig {
#if DEBUG
        let allowsLocalHTTP = true
#else
        let allowsLocalHTTP = false
#endif
        return AskChatConfig(
            endpointString: Self.configuredEndpointString(),
            timeout: Self.configuredTimeout(),
            allowsLocalHTTP: allowsLocalHTTP
        )
    }

    let endpointString: String
    let timeout: TimeInterval
    let allowsLocalHTTP: Bool

    var endpoint: URL? {
        Self.validatedEndpoint(endpointString, allowsLocalHTTP: allowsLocalHTTP)
    }

    var healthEndpoint: URL? {
        endpoint?
            .deletingLastPathComponent()
            .appendingPathComponent("health")
    }

    static func resolveEndpoint(
        environmentValue: String?,
        userDefaultsValue: String?,
        infoPlistValue: String?
    ) -> String {
        if let value = normalizedEndpoint(environmentValue) { return value }
        if let value = normalizedEndpoint(userDefaultsValue) { return value }
        if let value = normalizedEndpoint(infoPlistValue) { return value }
        return ""
    }

    private static func configuredEndpointString() -> String {
        let environment = ProcessInfo.processInfo.environment
        return resolveEndpoint(
            environmentValue: environment["ASK_CHAT_ENDPOINT"],
            userDefaultsValue: UserDefaults.standard.string(forKey: "AskChatEndpoint"),
            infoPlistValue: Bundle.main.object(forInfoDictionaryKey: "AskChatEndpoint") as? String
        )
    }

    private static func normalizedEndpoint(_ rawValue: String?) -> String? {
        guard let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              !value.hasPrefix("$(") else {
            return nil
        }
        return value
    }

    static func validatedEndpoint(_ value: String, allowsLocalHTTP: Bool) -> URL? {
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased(),
              !host.isEmpty,
              url.path == "/api/ask" else {
            return nil
        }
        if scheme == "https" { return url }
        guard scheme == "http", allowsLocalHTTP, isLocalDevelopmentHost(host) else { return nil }
        return url
    }

    private static func isLocalDevelopmentHost(_ host: String) -> Bool {
        if host.hasSuffix(".local") { return true }
        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4, parts.allSatisfy({ (0...255).contains($0) }) else { return false }
        return parts[0] == 10 ||
            (parts[0] == 172 && (16...31).contains(parts[1])) ||
            (parts[0] == 192 && parts[1] == 168)
    }

    private static func configuredTimeout() -> TimeInterval {
        let rawValue = ProcessInfo.processInfo.environment["ASK_CHAT_TIMEOUT_SECONDS"]
        guard let rawValue,
              let value = TimeInterval(rawValue),
              value > 0 else {
            return 12
        }
        return value
    }
}

protocol AskChatClient {
    var endpointDescription: String { get }
    var healthEndpointDescription: String? { get }

    func ask(_ request: AskChatRequest) async throws -> AskChatResponse
    func checkHealth() async throws -> AskServiceHealth
}

struct AskChatRequest: Encodable {
    let message: String
    let locale: String
    let timezone: String
}

struct AskServiceHealth: Decodable, Equatable {
    let ok: Bool
    let service: String?
    let endpoint: String?
    let deepSeek: DeepSeekStatus?

    struct DeepSeekStatus: Decodable, Equatable {
        let configured: Bool
        let model: String?
        let baseURL: String?

        enum CodingKeys: String, CodingKey {
            case configured
            case model
            case baseURL = "base_url"
        }
    }

    enum CodingKeys: String, CodingKey {
        case ok
        case service
        case endpoint
        case deepSeek = "deepseek"
    }
}

struct RemoteAskChatClient: AskChatClient {
    private let config: AskChatConfig
    private let session: URLSession

    init(config: AskChatConfig = .local, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    var endpointDescription: String {
        config.endpointString.isEmpty ? C.t("ask.endpointNotConfigured") : config.endpointString
    }

    var healthEndpointDescription: String? {
        config.healthEndpoint?.absoluteString
    }

    func ask(_ request: AskChatRequest) async throws -> AskChatResponse {
        guard let endpoint = config.endpoint else {
            throw AskChatClientError.invalidEndpoint(config.endpointString, allowsLocalHTTP: config.allowsLocalHTTP)
        }

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = config.timeout
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw AskChatClientError.transportFailed(
                endpoint: endpoint.absoluteString,
                reason: Self.transportReason(error)
            )
        }
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw AskChatClientError.badResponse(
                endpoint: endpoint.absoluteString,
                statusCode: (response as? HTTPURLResponse)?.statusCode,
                body: Self.bodySnippet(data)
            )
        }

        do {
            return try JSONDecoder().decode(AskChatResponse.self, from: data)
        } catch {
            throw AskChatClientError.decodingFailed(
                endpoint: endpoint.absoluteString,
                reason: error.localizedDescription,
                body: Self.bodySnippet(data)
            )
        }
    }

    func checkHealth() async throws -> AskServiceHealth {
        guard let endpoint = config.healthEndpoint else {
            throw AskChatClientError.invalidEndpoint(config.endpointString, allowsLocalHTTP: config.allowsLocalHTTP)
        }

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "GET"
        urlRequest.timeoutInterval = config.timeout

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw AskChatClientError.transportFailed(
                endpoint: endpoint.absoluteString,
                reason: Self.transportReason(error)
            )
        }
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw AskChatClientError.badResponse(
                endpoint: endpoint.absoluteString,
                statusCode: (response as? HTTPURLResponse)?.statusCode,
                body: Self.bodySnippet(data)
            )
        }

        do {
            return try JSONDecoder().decode(AskServiceHealth.self, from: data)
        } catch {
            throw AskChatClientError.decodingFailed(
                endpoint: endpoint.absoluteString,
                reason: error.localizedDescription,
                body: Self.bodySnippet(data)
            )
        }
    }

    private static func bodySnippet(_ data: Data) -> String {
        guard let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return ""
        }
        return String(text.prefix(600))
    }

    private static func transportReason(_ error: Error) -> String {
        guard let urlError = error as? URLError else {
            return error.localizedDescription
        }

        switch urlError.code {
        default:
            return urlError.localizedDescription
        }
    }
}

enum AskChatClientError: LocalizedError {
    case invalidEndpoint(String, allowsLocalHTTP: Bool)
    case transportFailed(endpoint: String, reason: String)
    case badResponse(endpoint: String, statusCode: Int?, body: String)
    case decodingFailed(endpoint: String, reason: String, body: String)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint(let endpoint, let allowsLocalHTTP):
            let current = endpoint.isEmpty ? C.t("ask.endpointNotConfigured") : endpoint
            let suggestion = allowsLocalHTTP
                ? C.t("ask.endpointDebugSuggestion")
                : C.t("ask.endpointReleaseSuggestion")
            return String(format: C.t("ask.endpointInvalidFormat"), current, suggestion)
        case .transportFailed(let endpoint, let reason):
            return "Ask service unavailable for \(endpoint): \(reason)"
        case .badResponse(let endpoint, let statusCode, let body):
            let status = statusCode.map(String.init) ?? "unknown"
            return body.isEmpty
                ? "Ask server returned HTTP \(status) for \(endpoint)"
                : "Ask server returned HTTP \(status) for \(endpoint): \(body)"
        case .decodingFailed(let endpoint, let reason, let body):
            return body.isEmpty
                ? "Ask response JSON decode failed for \(endpoint): \(reason)"
                : "Ask response JSON decode failed for \(endpoint): \(reason). Body: \(body)"
        }
    }
}
