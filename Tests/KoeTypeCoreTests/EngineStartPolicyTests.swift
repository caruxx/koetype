import XCTest
@testable import KoeTypeCore

final class EngineStartPolicyTests: XCTestCase {
    func testWorkThatNeverReportedBackIsGivenUp() {
        XCTAssertTrue(EngineStartPolicy.givesUp(work: 7, generation: 5, current: 5, lastCompleted: 6))
    }

    func testWorkThatReportedBackInTimeIsKept() {
        XCTAssertFalse(EngineStartPolicy.givesUp(work: 7, generation: 5, current: 5, lastCompleted: 7))
    }

    func testWorkOfAnEarlierRecordingIsNotJudgedAgain() {
        // The watchdog of recording 5's start fires after recording 6 began: only 6's own work may give up.
        XCTAssertFalse(EngineStartPolicy.givesUp(work: 7, generation: 5, current: 6, lastCompleted: 7))
        XCTAssertFalse(EngineStartPolicy.givesUp(work: 7, generation: 5, current: 6, lastCompleted: 6))
    }

    func testAStalledConfigurationChangeDuringTheRecordingIsGivenUp() {
        // Work 8 is the handling of a configuration change (Bluetooth profile switch) within recording 5,
        // begun after the start (work 7) had already reported back. It must be watched on its own.
        XCTAssertTrue(EngineStartPolicy.givesUp(work: 8, generation: 5, current: 5, lastCompleted: 7))
        XCTAssertFalse(EngineStartPolicy.givesUp(work: 8, generation: 5, current: 5, lastCompleted: 8))
    }

    func testWorkAlreadyGivenUpOnCountsAsCompleted() {
        // Giving up records the work number, so a late failure report for it must not be judged again.
        XCTAssertFalse(EngineStartPolicy.givesUp(work: 7, generation: 5, current: 5, lastCompleted: 7))
    }

    func testAStartedEngineThatStaysSilentIsGivenUp() {
        XCTAssertTrue(EngineStartPolicy.givesUpOnSilence(generation: 5, current: 5, recording: true, audioHeard: false))
    }

    func testAStartedEngineThatDeliveredAudioIsKept() {
        XCTAssertFalse(EngineStartPolicy.givesUpOnSilence(generation: 5, current: 5, recording: true, audioHeard: true))
    }

    func testSilenceIsNotJudgedAfterAShortTapOrForAnOlderRecording() {
        XCTAssertFalse(EngineStartPolicy.givesUpOnSilence(generation: 5, current: 5, recording: false, audioHeard: false))
        XCTAssertFalse(EngineStartPolicy.givesUpOnSilence(generation: 5, current: 6, recording: true, audioHeard: false))
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
        XCTAssertFalse(EngineStartPolicy.givesUp(work: 1, generation: 1, current: 2, lastCompleted: 1))
        // The second start finds the engine open and reports back at once.
        XCTAssertFalse(EngineStartPolicy.givesUp(work: 2, generation: 2, current: 2, lastCompleted: 2))
    }

    func testTimeoutIsAFewSeconds() {
        XCTAssertEqual(EngineStartPolicy.timeout, 3, accuracy: 0.001)
    }
}
