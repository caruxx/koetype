import Foundation

public protocol Polishing: Sendable {
    func polish(raw: String, dictionary: [DictionaryEntry]) async throws -> String
}

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public enum PolishError: Error, Equatable {
    case missingAPIKey, timeout, http(status: Int), badResponse
}

public struct URLSessionTransport: HTTPTransport {
    public init() {}

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PolishError.badResponse }
        return (data, http)
    }
}
