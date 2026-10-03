import XCTest
@testable import KoeTypeCore

final class LocalCleanupTests: XCTestCase {
    func testRemovesUnambiguousFillers() {
        XCTAssertEqual(LocalCleanup.clean("えーと、明日は休みです。"), "明日は休みです。")
        XCTAssertEqual(LocalCleanup.clean("明日は、えっと、休みです。"), "明日は、休みです。")
        XCTAssertEqual(LocalCleanup.clean("あのー明日なんですけど"), "明日なんですけど")
        XCTAssertEqual(LocalCleanup.clean("えー、それでは始めます。"), "それでは始めます。")
        XCTAssertEqual(LocalCleanup.clean("うーん、どうしようかな。"), "どうしようかな。")
        // Measured Whisper output: the hesitation "あのー" often arrives as "あの、".
        XCTAssertEqual(LocalCleanup.clean("えーと、あの、明日の会議なんですけど、えっと、10時からです。"),
                       "明日の会議なんですけど、10時からです。")
    }

    func testLeavesRealWordsAlone() {
        XCTAssertEqual(LocalCleanup.clean("あの人に連絡します。"), "あの人に連絡します。")
        XCTAssertEqual(LocalCleanup.clean("へえー、そうなんですね。"), "へえー、そうなんですね。")
        XCTAssertEqual(LocalCleanup.clean("明日の会議は10時からです。"), "明日の会議は10時からです。")
    }

    func testOnlyFillersBecomesEmpty() {
        XCTAssertEqual(LocalCleanup.clean("えーと。"), "")
        XCTAssertEqual(LocalCleanup.clean("えー"), "")
        XCTAssertEqual(LocalCleanup.clean("あのー、えっと"), "")
    }
}
