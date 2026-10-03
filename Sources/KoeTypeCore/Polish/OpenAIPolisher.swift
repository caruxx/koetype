import Foundation

public final class OpenAIPolisher: Polishing, @unchecked Sendable {
    private let apiKey: @Sendable () -> String?
    private let model: @Sendable () -> String
    private let transport: HTTPTransport
    private let timeout: @Sendable (Int) -> Double

    public init(apiKey: @escaping @Sendable () -> String?,
                model: @escaping @Sendable () -> String,
                transport: HTTPTransport = URLSessionTransport(),
                timeout: @escaping @Sendable (Int) -> Double = PolishValidator.timeoutSeconds(forCharacterCount:)) {
        self.apiKey = apiKey; self.model = model; self.transport = transport; self.timeout = timeout
    }

    public func polish(raw: String, dictionary: [DictionaryEntry]) async throws -> String {
        var request = try authorized(URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model(),
            "messages": [
                ["role": "system", "content": PolishPrompt.system(dictionary: dictionary)],
                ["role": "user", "content": PolishPrompt.user(raw: raw)],
            ],
        ])
        let data = try await send(request, timeout: timeout(raw.count))
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else { throw PolishError.badResponse }
        return content
    }

    public func listModels() async throws -> [String] {
        let request = try authorized(URL(string: "https://api.openai.com/v1/models")!)
        let data = try await send(request, timeout: 10)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["data"] as? [[String: Any]] else { throw PolishError.badResponse }
        return list.compactMap { $0["id"] as? String }.sorted()
    }

    private func authorized(_ url: URL) throws -> URLRequest {
        guard let key = apiKey()?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            throw PolishError.missingAPIKey
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func send(_ request: URLRequest, timeout seconds: Double) async throws -> Data {
        let transport = self.transport
        return try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                let (data, response) = try await transport.send(request)
                guard (200..<300).contains(response.statusCode) else {
                    throw PolishError.http(status: response.statusCode)
                }
                return data
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw PolishError.timeout
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }
}
