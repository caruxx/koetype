import XCTest
@testable import KoeTypeCore

final class EngineStartPolicyTests: XCTestCase {
    func testAStartThatNeverReportedBackIsGivenUp() {
        XCTAssertTrue(EngineStartPolicy.givesUp(started: 5, current: 5, lastCompleted: 4))
    }

    func testAStartThatReportedBackInTimeIsKept() {
        XCTAssertFalse(EngineStartPolicy.givesUp(started: 5, current: 5, lastCompleted: 5))
    }

    func testAStartOfAnEarlierRecordingIsNotJudgedAgain() {
        // The watchdog of recording 5 fires after recording 6 began: only 6's own watchdog may give up.
        XCTAssertFalse(EngineStartPolicy.givesUp(started: 5, current: 6, lastCompleted: 5))
        XCTAssertFalse(EngineStartPolicy.givesUp(started: 5, current: 6, lastCompleted: 4))
    }

    func testAnEngineThatCameUpInTimeIsAccepted() {
        XCTAssertTrue(EngineStartPolicy.acceptsEngine(abandoned: false, started: 3, current: 3))
    }

    func testAnEngineTheRecorderGaveUpOnIsNeverUsed() {
        XCTAssertFalse(EngineStartPolicy.acceptsEngine(abandoned: true, started: 3, current: 3))
        XCTAssertFalse(EngineStartPolicy.acceptsEngine(abandoned: true, started: 3, current: 4))
    }

    func testAnEngineMadeForAnOlderRecordingIsNotUsedForANewerOne() {
        XCTAssertFalse(EngineStartPolicy.acceptsEngine(abandoned: false, started: 3, current: 4))
    }

    func testTimeoutIsAFewSeconds() {
        XCTAssertEqual(EngineStartPolicy.timeout, 3, accuracy: 0.001)
    }
}
