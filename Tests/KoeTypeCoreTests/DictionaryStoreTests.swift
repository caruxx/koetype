import XCTest
@testable import KoeTypeCore

final class DictionaryStoreTests: XCTestCase {
    var url: URL!
    override func setUp() {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("dictionary.json")
    }
    override func tearDown() { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    func testAddPersistsAndListsNewestFirst() throws {
        let store = DictionaryStore(fileURL: url)
        try store.add(term: "カルビスター", variants: ["かるびすたー"], now: Date(timeIntervalSince1970: 1))
        try store.add(term: "ASIN", variants: ["エーシン"], now: Date(timeIntervalSince1970: 2))
        XCTAssertEqual(store.entries.map(\.term), ["ASIN", "カルビスター"])
        XCTAssertEqual(DictionaryStore(fileURL: url).entries.map(\.term), ["ASIN", "カルビスター"])
    }

    func testAddTrimsAndRejectsEmptyAndDuplicate() throws {
        let store = DictionaryStore(fileURL: url)
        try store.add(term: "  SP-API ", variants: [], now: Date())
        XCTAssertEqual(store.entries.first?.term, "SP-API")
        XCTAssertThrowsError(try store.add(term: "   ", variants: [], now: Date()))
        XCTAssertThrowsError(try store.add(term: "SP-API", variants: [], now: Date()))
    }

    func testUpdateAndRemove() throws {
        let store = DictionaryStore(fileURL: url)
        var entry = try store.add(term: "FBA", variants: [], now: Date())
        entry.variants = ["エフビーエー"]
        try store.update(entry)
        XCTAssertEqual(store.entries.first?.variants, ["エフビーエー"])
        try store.remove(id: entry.id)
        XCTAssertTrue(store.entries.isEmpty)
    }

    func testHintTextNeverExceedsLimitAndPrefersNewest() throws {
        let store = DictionaryStore(fileURL: url)
        try store.add(term: "あいうえお", variants: [], now: Date(timeIntervalSince1970: 1))
        try store.add(term: "かきくけこ", variants: [], now: Date(timeIntervalSince1970: 2))
        try store.add(term: "さしすせそ", variants: [], now: Date(timeIntervalSince1970: 3))
        XCTAssertEqual(store.hintText(maxCharacters: 11), "さしすせそ、かきくけこ")
        XCTAssertEqual(store.hintText(maxCharacters: 4), "")
        XCTAssertEqual(store.hintText(maxCharacters: 100), "さしすせそ、かきくけこ、あいうえお")
    }
    func testLongNewestEntryDoesNotHideShorterFollowingHints() throws {
        let store = DictionaryStore(fileURL: url)
        try store.add(term: "API", variants: [], now: Date(timeIntervalSince1970: 1))
        try store.add(term: String(repeating: "長", count: 20), variants: [], now: Date(timeIntervalSince1970: 2))
        XCTAssertEqual(store.hintText(maxCharacters: 5), "API")
        XCTAssertEqual(store.hintText(maxCharacters: 0), "")
    }

}
