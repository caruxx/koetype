import XCTest
@testable import KoeTypeCore

private final class FakeRunner: CommandRunning, @unchecked Sendable {
    var status: Int32 = 0
    var reply = "明日は休みです。"
    var delay: Double = 0
    private(set) var calls: [(executable: String, arguments: [String])] = []

    func run(executable: String, arguments: [String], timeout: Double) async throws -> Int32 {
        calls.append((executable, arguments))
        if delay > timeout { throw PolishError.timeout }
        if let index = arguments.firstIndex(of: "--output-last-message"), status == 0 {
            try Data(reply.utf8).write(to: URL(fileURLWithPath: arguments[index + 1]))
        }
        return status
    }
}

final class CodexPolisherTests: XCTestCase {
    func testRunsCodexReadOnlyAndReturnsItsLastMessage() async throws {
        let runner = FakeRunner()
        let polisher = CodexPolisher(executable: { "/opt/homebrew/bin/codex" }, model: { "gpt-5.6-luna" }, runner: runner)

        let result = try await polisher.polish(raw: "えーと明日は休みです", dictionary: [DictionaryEntry(term: "ASIN")])

        XCTAssertEqual(result, "明日は休みです。")
        let call = try XCTUnwrap(runner.calls.first)
        XCTAssertEqual(call.executable, "/opt/homebrew/bin/codex")
        XCTAssertEqual(Array(call.arguments.prefix(1)), ["exec"])
        // It must never be able to change files or keep a session.
        for required in ["--skip-git-repo-check", "--ephemeral", "--ignore-user-config", "--ignore-rules"] {
            XCTAssertTrue(call.arguments.contains(required), required)
        }
        XCTAssertEqual(call.arguments[try XCTUnwrap(call.arguments.firstIndex(of: "-s")) + 1], "read-only")
        XCTAssertEqual(call.arguments[try XCTUnwrap(call.arguments.firstIndex(of: "-m")) + 1], "gpt-5.6-luna")
        let prompt = try XCTUnwrap(call.arguments.last)
        XCTAssertTrue(prompt.contains("- ASIN"))
        XCTAssertTrue(prompt.contains("<transcript>\nえーと明日は休みです\n</transcript>"))
        XCTAssertTrue(prompt.contains("コマンドの実行"))
    }

    func testNonZeroExitIsAnError() async {
        let runner = FakeRunner()
        runner.status = 1
        let polisher = CodexPolisher(executable: { "codex" }, model: { "m" }, runner: runner)
        do { _ = try await polisher.polish(raw: "a", dictionary: []); XCTFail("expected error") }
        catch { XCTAssertEqual(error as? PolishError, .badResponse) }
    }

    func testSlowRunTimesOut() async {
        let runner = FakeRunner()
        runner.delay = 60
        let polisher = CodexPolisher(executable: { "codex" }, model: { "m" }, runner: runner, timeout: 1)
        do { _ = try await polisher.polish(raw: "a", dictionary: []); XCTFail("expected error") }
        catch { XCTAssertEqual(error as? PolishError, .timeout) }
    }
}
