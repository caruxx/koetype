import XCTest
@testable import KoeTypeCore

final class JSONFileStoreTests: XCTestCase {
    var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    func testMissingFileLoadsEmpty() {
        let store = JSONFileStore<String>(fileURL: dir.appendingPathComponent("a.json"))
        XCTAssertEqual(store.load(), [])
    }

    func testSaveCreatesDirectoryAndRoundTrips() throws {
        let store = JSONFileStore<String>(fileURL: dir.appendingPathComponent("nested/a.json"))
        try store.save(["カルビスター", "SP-API"])
        XCTAssertEqual(store.load(), ["カルビスター", "SP-API"])
    }

    func testCorruptFileIsMovedAsideNotOverwritten() throws {
        let url = dir.appendingPathComponent("a.json")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("[\"half written".utf8).write(to: url)
        let store = JSONFileStore<String>(fileURL: url)

        XCTAssertEqual(store.load(), [])

        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        let aside = names.filter { $0.hasPrefix("a.json.corrupt-") }
        XCTAssertEqual(aside.count, 1)
        let kept = try Data(contentsOf: dir.appendingPathComponent(aside[0]))
        XCTAssertEqual(String(decoding: kept, as: UTF8.self), "[\"half written")
        XCTAssertFalse(names.contains("a.json"))
    }

    func testTwoCorruptFilesInTheSameSecondAreBothKept() throws {
        let url = dir.appendingPathComponent("a.json")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = JSONFileStore<String>(fileURL: url)
        try Data("first broken".utf8).write(to: url)
        _ = store.load()
        try Data("second broken".utf8).write(to: url)
        _ = store.load()
        let aside = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.contains(".corrupt-") }
        XCTAssertEqual(aside.count, 2)
        XCTAssertNoThrow(try store.save(["ok"]))
    }

    func testUnreadableFileIsNeverOverwritten() throws {
        let url = dir.appendingPathComponent("a.json")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("[\"precious\"]".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path) }
        let store = JSONFileStore<String>(fileURL: url)

        XCTAssertEqual(store.load(), [])
        XCTAssertThrowsError(try store.save(["replacement"]))

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        XCTAssertEqual(String(decoding: try Data(contentsOf: url), as: UTF8.self), "[\"precious\"]")
    }
}
