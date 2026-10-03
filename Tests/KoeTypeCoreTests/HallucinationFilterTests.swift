import XCTest
@testable import KoeTypeCore

final class HallucinationFilterTests: XCTestCase {
    func testKnownPhantomPhrasesBecomeEmpty() {
        XCTAssertEqual(HallucinationFilter.clean("ご視聴ありがとうございました"), "")
        XCTAssertEqual(HallucinationFilter.clean(" ご視聴ありがとうございました。 "), "")
        XCTAssertEqual(HallucinationFilter.clean("チャンネル登録お願いします!"), "")
        XCTAssertEqual(HallucinationFilter.clean("(音楽)"), "")
        XCTAssertEqual(HallucinationFilter.clean("   \n"), "")
    }

    func testRealSpeechIsKeptAndTrimmed() {
        XCTAssertEqual(HallucinationFilter.clean(" 明日の会議は10時からです "), "明日の会議は10時からです")
        // A phantom phrase inside real speech must survive: the user may really say it.
        XCTAssertEqual(HallucinationFilter.clean("動画の最後にご視聴ありがとうございましたと入れてください"),
                       "動画の最後にご視聴ありがとうございましたと入れてください")
    }
}
