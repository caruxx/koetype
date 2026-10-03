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

public protocol Transcribing: Sendable {
    func transcribe(samples: [Float], hints: String) async throws -> String
}

public struct DeliveryResult: Equatable, Sendable {
    public var outcome: DeliveryOutcome
    public var appName: String?

    public init(outcome: DeliveryOutcome, appName: String?) {
        self.outcome = outcome; self.appName = appName
    }
}

public protocol TextDelivering: Sendable {
    func deliver(_ text: String) async -> DeliveryResult
}

public enum PipelineStatus: Equatable, Sendable {
    case transcribing, polishing
    case delivered(DeliveryOutcome, polished: Bool)
    case nothingHeard
    case failed(String)
}
