import XCTest
@testable import KoeTypeCore

final class LevelMeterTests: XCTestCase {
    func testQuietSpeechIsClearlyVisibleAndSilenceIsNot() {
        XCTAssertLessThan(LevelMeter.display(rms: 0.0005), 0.1)
        XCTAssertGreaterThan(LevelMeter.display(rms: 0.02), 0.3)
        XCTAssertEqual(LevelMeter.display(rms: 1), 1)
        XCTAssertEqual(LevelMeter.display(rms: 0), 0)
    }

    func testHistoryKeepsTheMostRecentLevelsInOrder() {
        var history = LevelHistory(capacity: 3)
        XCTAssertEqual(history.values, [0, 0, 0])
        for level in [0.1, 0.2, 0.3, 0.4] as [Float] { history.push(level) }
        XCTAssertEqual(history.values, [0.2, 0.3, 0.4])
        history.reset()
        XCTAssertEqual(history.values, [0, 0, 0])
    }

    func testHeardSomethingOnlyAfterALevelAboveTheSpeechFloor() {
        var history = LevelHistory(capacity: 3)
        history.push(0.05)
        XCTAssertFalse(history.heardSpeech)
        history.push(0.4)
        XCTAssertTrue(history.heardSpeech)
        history.reset()
        XCTAssertFalse(history.heardSpeech)
    }
}
