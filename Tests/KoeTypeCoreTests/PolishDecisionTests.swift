import XCTest
@testable import KoeTypeCore

final class PolishDecisionTests: XCTestCase {
    func testShortTextStaysLocal() {
        XCTAssertFalse(PolishDecision.shouldUseAI(for: "了解です。", minimumCharacters: 20))
        // Punctuation does not count toward the length.
        XCTAssertFalse(PolishDecision.shouldUseAI(for: "はい、分かりました。ありがとうございます。", minimumCharacters: 20))
    }

    func testLongTextGoesToAI() {
        XCTAssertTrue(PolishDecision.shouldUseAI(for: "来週の火曜日の午後3時から打ち合わせをお願いします。", minimumCharacters: 20))
    }

    func testZeroMinimumSendsEverything() {
        XCTAssertTrue(PolishDecision.shouldUseAI(for: "はい", minimumCharacters: 0))
    }
}
