import XCTest
@testable import KoeTypeCore

final class EngineStartPolicyTests: XCTestCase {
    func testWorkThatNeverReportedBackIsGivenUp() {
        XCTAssertTrue(EngineStartPolicy.givesUp(work: 7, generation: 5, current: 5, pending: [7]))
    }

    func testWorkThatReportedBackInTimeIsKept() {
        XCTAssertFalse(EngineStartPolicy.givesUp(work: 7, generation: 5, current: 5, pending: []))
    }

    func testWorkOfAnEarlierRecordingIsNotJudgedAgain() {
        // The watchdog of recording 5's start fires after recording 6 began: only 6's own work may give up.
        XCTAssertFalse(EngineStartPolicy.givesUp(work: 7, generation: 5, current: 6, pending: []))
        XCTAssertFalse(EngineStartPolicy.givesUp(work: 7, generation: 5, current: 6, pending: [7]))
    }

    func testAStalledConfigurationChangeDuringTheRecordingIsGivenUp() {
        // Work 8 is the handling of a configuration change (Bluetooth profile switch) within recording 5,
        // begun after the start (work 7) had already reported back. It must be watched on its own.
        XCTAssertTrue(EngineStartPolicy.givesUp(work: 8, generation: 5, current: 5, pending: [8]))
        XCTAssertFalse(EngineStartPolicy.givesUp(work: 8, generation: 5, current: 5, pending: []))
    }

    func testWorkAlreadyGivenUpOnCountsAsCompleted() {
        // Giving up removes the work number, so a late failure report for it must not be judged again.
        XCTAssertFalse(EngineStartPolicy.givesUp(work: 7, generation: 5, current: 5, pending: []))
    }

    func testWorkFinishedOutOfOrderDoesNotCompleteEarlierWork() {
        // A configuration-change thread begins work 8 and a restart inside it finishes 8 (and 9) before
        // the start numbered 7 has even run on the queue. 7 then stalls: it must still be given up on.
        XCTAssertTrue(EngineStartPolicy.givesUp(work: 7, generation: 5, current: 5, pending: [7]))
        XCTAssertFalse(EngineStartPolicy.givesUp(work: 8, generation: 5, current: 5, pending: [7]))
        XCTAssertFalse(EngineStartPolicy.givesUp(work: 9, generation: 5, current: 5, pending: [7]))
    }

    private func verdict(generation: Int = 5, current: Int = 5, recording: Bool = true, audioHeard: Bool = false,
                         changePending: Bool = false) -> EngineStartPolicy.SilenceVerdict {
        EngineStartPolicy.silenceVerdict(generation: generation, current: current, recording: recording,
                                         audioHeard: audioHeard, changePending: changePending)
    }

    func testAStartedEngineThatStaysSilentIsGivenUp() {
        XCTAssertEqual(verdict(), .giveUp)
    }

    func testAStartedEngineThatDeliveredAudioIsKept() {
        XCTAssertEqual(verdict(audioHeard: true), .keep)
        XCTAssertEqual(verdict(audioHeard: true, changePending: true), .keep)
    }

    func testSilenceIsNotJudgedAfterAShortTapOrForAnOlderRecording() {
        XCTAssertEqual(verdict(recording: false), .keep)
        XCTAssertEqual(verdict(current: 6), .keep)
        XCTAssertEqual(verdict(recording: false, changePending: true), .keep)
        XCTAssertEqual(verdict(current: 6, changePending: true), .keep)
    }

    func testSilenceIsPutOffWhileAConfigurationChangeIsBeingHandled() {
        // A Bluetooth profile switch before the first buffer: the change is noted, its device query takes
        // a while, then restart attempts fail and back off. The watch from the first start fires anywhere
        // in that stretch, even before any restart began; it must not give up but ask again later.
        XCTAssertEqual(verdict(changePending: true), .checkAgain)
        // Once the handling is over (a restart armed a fresh watch, or none was needed), silence counts again.
        XCTAssertEqual(verdict(changePending: false), .giveUp)
    }

    func testHeardIsCountedSinceTheLastRestartNotSinceTheFirstStart() {
        // The recorder resets `audioHeard` when it arms the watch of a successful restart, so a restart
        // that "succeeds" and then delivers nothing is judged on what arrived after it.
        XCTAssertEqual(verdict(audioHeard: false), .giveUp)
    }

    func testOnlyTheCurrentWorkerArmsTheSilenceWatchForTheCurrentRecording() {
        XCTAssertTrue(EngineStartPolicy.armsSilenceWatch(workerCurrent: true, abandoned: false, generation: 5, current: 5))
        // A worker already replaced, or given up on, reports late: it must not overwrite the new watch.
        XCTAssertFalse(EngineStartPolicy.armsSilenceWatch(workerCurrent: false, abandoned: false, generation: 5, current: 5))
        XCTAssertFalse(EngineStartPolicy.armsSilenceWatch(workerCurrent: true, abandoned: true, generation: 5, current: 5))
        // A restart for an older recording that finishes late arms nothing for the newer one.
        XCTAssertFalse(EngineStartPolicy.armsSilenceWatch(workerCurrent: true, abandoned: false, generation: 5, current: 6))
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
        XCTAssertFalse(EngineStartPolicy.givesUp(work: 1, generation: 1, current: 2, pending: []))
        // The second start finds the engine open and reports back at once.
        XCTAssertFalse(EngineStartPolicy.givesUp(work: 2, generation: 2, current: 2, pending: []))
    }

    func testTimeoutIsAFewSeconds() {
        XCTAssertEqual(EngineStartPolicy.timeout, 3, accuracy: 0.001)
    }
}
