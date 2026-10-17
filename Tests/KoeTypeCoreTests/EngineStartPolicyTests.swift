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

    func testAnEngineThatCameUpIsKept() {
        XCTAssertTrue(EngineStartPolicy.acceptsEngine(abandoned: false))
    }

    func testAnEngineTheRecorderGaveUpOnIsNeverUsed() {
        XCTAssertFalse(EngineStartPolicy.acceptsEngine(abandoned: true))
    }

    func testAnEngineThatCameUpAfterAShortTapIsKeptForTheSecondPress() {
        // The second press of a double tap bumps the generation before a cold Bluetooth engine is up.
        // The engine still counts as started, so keep-open and the next start find it instead of
        // opening the microphone again (another profile switch, the case that stalls the HAL), and
        // neither recording's watchdog gives up on the worker once the start has reported back.
        XCTAssertTrue(EngineStartPolicy.acceptsEngine(abandoned: false))
        XCTAssertFalse(EngineStartPolicy.givesUp(started: 1, current: 2, lastCompleted: 1))
        // The second start finds the engine open and reports back at once.
        XCTAssertFalse(EngineStartPolicy.givesUp(started: 2, current: 2, lastCompleted: 2))
    }

    func testTimeoutIsAFewSeconds() {
        XCTAssertEqual(EngineStartPolicy.timeout, 3, accuracy: 0.001)
    }
}
