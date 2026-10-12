import XCTest
@testable import KoeTypeCore

final class UsageStoreTests: XCTestCase {
    var url: URL!
    override func setUp() {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("usage.json")
    }
    override func tearDown() { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    func testAccumulatesPerMonthAndPersists() throws {
        let store = UsageStore(fileURL: url, timeZone: TimeZone(identifier: "Asia/Tokyo")!)
        try store.record(PolishUsage(inputTokens: 700, outputTokens: 50), at: date("2026-10-03T12:00:00Z"))
        try store.record(PolishUsage(inputTokens: 800, outputTokens: 70), at: date("2026-10-20T12:00:00Z"))
        try store.record(PolishUsage(inputTokens: 100, outputTokens: 10), at: date("2026-11-01T12:00:00Z"))

        let october = store.month(containing: date("2026-10-15T00:00:00Z"))
        XCTAssertEqual(october, MonthlyUsage(month: "2026-10", requests: 2, inputTokens: 1500, outputTokens: 120))
        let reloaded = UsageStore(fileURL: url, timeZone: TimeZone(identifier: "Asia/Tokyo")!)
        XCTAssertEqual(reloaded.month(containing: date("2026-11-02T00:00:00Z")).requests, 1)
    }

    func testMonthBoundaryUsesTheLocalTimeZone() throws {
        let store = UsageStore(fileURL: url, timeZone: TimeZone(identifier: "Asia/Tokyo")!)
        // 2026-10-31 16:00 UTC is already November 1st in Tokyo.
        try store.record(PolishUsage(inputTokens: 1, outputTokens: 1), at: date("2026-10-31T16:00:00Z"))
        XCTAssertEqual(store.month(containing: date("2026-10-31T16:00:00Z")).month, "2026-11")
    }

    func testEmptyMonthIsZero() {
        let store = UsageStore(fileURL: url, timeZone: TimeZone(identifier: "Asia/Tokyo")!)
        XCTAssertEqual(store.month(containing: date("2026-10-03T00:00:00Z")),
                       MonthlyUsage(month: "2026-10", requests: 0, inputTokens: 0, outputTokens: 0))
    }

    func testEstimatedCostInYen() {
        let usage = MonthlyUsage(month: "2026-10", requests: 9000, inputTokens: 6_750_000, outputTokens: 540_000)
        // 6.75 M input at $0.10 + 0.54 M output at $0.50 = $0.945; at 150 yen per dollar = 141.75 yen.
        XCTAssertEqual(usage.estimatedYen(inputDollarsPerMillion: 0.10, outputDollarsPerMillion: 0.50, yenPerDollar: 150),
                       141.75, accuracy: 0.001)
    }
}
