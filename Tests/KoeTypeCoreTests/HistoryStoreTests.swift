import XCTest
@testable import KoeTypeCore

private enum LegacyOutcome: String, Decodable { case inserted, copyBox, insertedAndCopyBox }
private struct LegacyHistoryItem: Decodable {
    let id: UUID
    let date: Date
    let rawText: String
    let finalText: String
    let appName: String?
    let outcome: LegacyOutcome
    let polished: Bool
    let durationSeconds: Double
}

final class HistoryStoreTests: XCTestCase {
    var url: URL!
    override func setUp() {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("history.json")
    }
    override func tearDown() { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    private func item(_ text: String, at seconds: TimeInterval) -> HistoryItem {
        HistoryItem(date: Date(timeIntervalSince1970: seconds), rawText: text + " raw", finalText: text,
                    appName: "メモ", outcome: .inserted, polished: true, durationSeconds: 2)
    }

    func testAppendIsNewestFirstAndPersists() throws {
        let store = HistoryStore(fileURL: url)
        try store.append(item("一つ目", at: 1))
        try store.append(item("二つ目", at: 2))
        XCTAssertEqual(store.items.map(\.finalText), ["二つ目", "一つ目"])
        XCTAssertEqual(HistoryStore(fileURL: url).items.map(\.finalText), ["二つ目", "一つ目"])
    }

    func testLimitDropsOldest() throws {
        let store = HistoryStore(fileURL: url, limit: 3)
        for i in 1...5 { try store.append(item("item\(i)", at: TimeInterval(i))) }
        XCTAssertEqual(store.items.map(\.finalText), ["item5", "item4", "item3"])
    }

    func testSearchMatchesFinalOrRawCaseInsensitive() throws {
        let store = HistoryStore(fileURL: url)
        try store.append(item("SP-APIの件", at: 1))
        try store.append(item("会議は10時", at: 2))
        XCTAssertEqual(store.search("sp-api").map(\.finalText), ["SP-APIの件"])
        XCTAssertEqual(store.search("raw").count, 2)
        XCTAssertEqual(store.search("").count, 2)
    }

    func testRemove() throws {
        let store = HistoryStore(fileURL: url)
        let target = item("消す", at: 1)
        try store.append(target)
        try store.remove(id: target.id)
        XCTAssertTrue(store.items.isEmpty)
    }

    func testNewAndLegacyDeliveryOutcomesRemainReadable() throws {
        let store = HistoryStore(fileURL: url)
        var legacy = item("旧履歴", at: 1)
        legacy.outcome = .insertedAndCopyBox
        var current = item("新履歴", at: 2)
        current.outcome = .unverified
        var notPasted = item("未送出", at: 3)
        notPasted.outcome = .notPasted
        try store.append(legacy)
        try store.append(current)
        try store.append(notPasted)
        XCTAssertEqual(HistoryStore(fileURL: url).items.map(\.outcome),
                       [.notPasted, .unverified, .insertedAndCopyBox])
        // The installed older app must decode the entire file rather than move it
        // aside as corrupt because it does not know the new enum case.
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let legacyReader = try decoder.decode([LegacyHistoryItem].self, from: Data(contentsOf: url))
        XCTAssertEqual(legacyReader.map(\.outcome), [.copyBox, .copyBox, .insertedAndCopyBox])
    }
}
