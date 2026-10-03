import XCTest
@testable import KoeTypeCore

final class PolishValidatorTests: XCTestCase {
    func testAcceptsNormalResultAndTrims() {
        XCTAssertEqual(PolishValidator.accept(polished: " 明日は休みです。\n", raw: "えーと明日は休みです"),
                       "明日は休みです。")
    }

    func testStripsEchoedWrapperTags() {
        XCTAssertEqual(PolishValidator.accept(polished: "<transcript>\n明日は休みです。\n</transcript>",
                                              raw: "明日は休みです"), "明日は休みです。")
    }

    func testRejectsEmpty() {
        XCTAssertNil(PolishValidator.accept(polished: "  ", raw: "明日は休みです"))
    }

    func testRejectsWhenFarLongerThanRaw() {
        let raw = String(repeating: "あ", count: 20)
        XCTAssertNotNil(PolishValidator.accept(polished: String(repeating: "い", count: 40), raw: raw))
        XCTAssertNil(PolishValidator.accept(polished: String(repeating: "い", count: 41), raw: raw))
    }

    func testShortRawAllowsPunctuationGrowth() {
        // "はい" -> "はい。" is 1.5x; a 2-character input may grow by up to 10 characters.
        XCTAssertEqual(PolishValidator.accept(polished: "はい。", raw: "はい"), "はい。")
        XCTAssertNil(PolishValidator.accept(polished: String(repeating: "あ", count: 13), raw: "はい"))
    }

    func testTimeoutGrowsWithLengthAndIsCapped() {
        XCTAssertEqual(PolishValidator.timeoutSeconds(forCharacterCount: 0), 3)
        XCTAssertEqual(PolishValidator.timeoutSeconds(forCharacterCount: 199), 3)
        XCTAssertEqual(PolishValidator.timeoutSeconds(forCharacterCount: 200), 4)
        XCTAssertEqual(PolishValidator.timeoutSeconds(forCharacterCount: 1000), 8)
        XCTAssertEqual(PolishValidator.timeoutSeconds(forCharacterCount: 100_000), 15)
    }
}
