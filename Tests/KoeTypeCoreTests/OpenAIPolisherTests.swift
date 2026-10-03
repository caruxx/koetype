import XCTest
@testable import KoeTypeCore

private final class StubTransport: HTTPTransport, @unchecked Sendable {
    var status = 200
    var body = Data()
    var delay: Double = 0
    private(set) var requests: [URLRequest] = []

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (body, response)
    }
}

final class OpenAIPolisherTests: XCTestCase {
    private func completion(_ text: String) -> Data {
        try! JSONSerialization.data(withJSONObject: ["choices": [["message": ["role": "assistant", "content": text]]]])
    }

    func testSendsChatCompletionRequestAndReturnsContent() async throws {
        let transport = StubTransport()
        transport.body = completion("明日は休みです。")
        let polisher = OpenAIPolisher(apiKey: { "test-key" }, model: { "model-x" }, transport: transport)

        let result = try await polisher.polish(raw: "えーと明日は休みです", dictionary: [DictionaryEntry(term: "ASIN")])

        XCTAssertEqual(result, "明日は休みです。")
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/chat/completions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "model-x")
        XCTAssertNil(json["temperature"])   // newer models reject non-default temperature
        let messages = try XCTUnwrap(json["messages"] as? [[String: String]])
        XCTAssertEqual(messages.map { $0["role"] }, ["system", "user"])
        XCTAssertTrue(messages[0]["content"]!.contains("- ASIN"))
        XCTAssertEqual(messages[1]["content"], "<transcript>\nえーと明日は休みです\n</transcript>")
    }

    func testMissingKeyThrowsWithoutSending() async {
        let transport = StubTransport()
        let polisher = OpenAIPolisher(apiKey: { nil }, model: { "m" }, transport: transport)
        await assertThrows(PolishError.missingAPIKey) { try await polisher.polish(raw: "a", dictionary: []) }
        XCTAssertTrue(transport.requests.isEmpty)
        let blank = OpenAIPolisher(apiKey: { "  " }, model: { "m" }, transport: transport)
        await assertThrows(PolishError.missingAPIKey) { try await blank.polish(raw: "a", dictionary: []) }
    }

    func testHTTPErrorThrows() async {
        let transport = StubTransport()
        transport.status = 429
        let polisher = OpenAIPolisher(apiKey: { "test-key" }, model: { "m" }, transport: transport)
        await assertThrows(PolishError.http(status: 429)) { try await polisher.polish(raw: "a", dictionary: []) }
    }

    func testMalformedBodyThrows() async {
        let transport = StubTransport()
        transport.body = Data("{}".utf8)
        let polisher = OpenAIPolisher(apiKey: { "test-key" }, model: { "m" }, transport: transport)
        await assertThrows(PolishError.badResponse) { try await polisher.polish(raw: "a", dictionary: []) }
    }

    func testSlowResponseTimesOut() async {
        let transport = StubTransport()
        transport.delay = 2
        transport.body = completion("x")
        let polisher = OpenAIPolisher(apiKey: { "test-key" }, model: { "m" }, transport: transport, timeout: { _ in 0.05 })
        let started = Date()
        await assertThrows(PolishError.timeout) { try await polisher.polish(raw: "a", dictionary: []) }
        XCTAssertLessThan(Date().timeIntervalSince(started), 1)
    }

    func testListModelsReturnsSortedIDs() async throws {
        let transport = StubTransport()
        transport.body = try JSONSerialization.data(withJSONObject: ["data": [["id": "b-model"], ["id": "a-model"]]])
        let polisher = OpenAIPolisher(apiKey: { "test-key" }, model: { "m" }, transport: transport)
        let models = try await polisher.listModels()
        XCTAssertEqual(models, ["a-model", "b-model"])
        XCTAssertEqual(transport.requests.first?.url?.absoluteString, "https://api.openai.com/v1/models")
    }

    private func assertThrows(_ expected: PolishError, _ body: () async throws -> Any,
                              file: StaticString = #filePath, line: UInt = #line) async {
        do { _ = try await body(); XCTFail("expected \(expected)", file: file, line: line) }
        catch { XCTAssertEqual(error as? PolishError, expected, file: file, line: line) }
    }
}
