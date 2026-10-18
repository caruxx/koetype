import XCTest
@testable import KoeTypeCore

final class RecordingLimitTests: XCTestCase {
    func testTheLimitIsReachedAfterMaxSecondsRegardlessOfSamples() {
        XCTAssertTrue(RecordingLimit.reached(elapsedSeconds: 7_200, maxSeconds: 7_200))
        XCTAssertTrue(RecordingLimit.reached(elapsedSeconds: 7_201, maxSeconds: 7_200))
    }

    func testTheLimitIsNotReachedBefore() {
        XCTAssertFalse(RecordingLimit.reached(elapsedSeconds: 7_199, maxSeconds: 7_200))
        XCTAssertFalse(RecordingLimit.reached(elapsedSeconds: 0, maxSeconds: 7_200))
    }

    func testRemainingTimeIsWhatIsLeftAndNeverNegative() {
        // A sleep that woke early (or a monotonic clock that ran a little behind) waits for the rest.
        XCTAssertEqual(RecordingLimit.remainingSeconds(elapsedSeconds: 7_100, maxSeconds: 7_200), 100, accuracy: 0.001)
        XCTAssertEqual(RecordingLimit.remainingSeconds(elapsedSeconds: 7_300, maxSeconds: 7_200), 0, accuracy: 0.001)
    }
}

final class RecordingSessionPhaseTests: XCTestCase {
    func testOnlyIdleAcceptsAStartOrAFileTranscription() {
        XCTAssertTrue(RecordingSessionPhase.idle.acceptsStart)
        // While the first start is still opening the Mac's sound, a second start or a file job must wait.
        XCTAssertFalse(RecordingSessionPhase.starting.acceptsStart)
        XCTAssertFalse(RecordingSessionPhase.recording.acceptsStart)
        // A running file transcription blocks the start of a recording as well.
        XCTAssertFalse(RecordingSessionPhase.transcribing.acceptsStart)
    }

    func testOnlyARunningRecordingCanBeStopped() {
        XCTAssertTrue(RecordingSessionPhase.recording.acceptsStop)
        XCTAssertFalse(RecordingSessionPhase.starting.acceptsStop)
        XCTAssertFalse(RecordingSessionPhase.idle.acceptsStop)
        XCTAssertFalse(RecordingSessionPhase.transcribing.acceptsStop)
    }

    func testTheEndOfATranscriptionDoesNotClobberARecording() {
        XCTAssertTrue(RecordingSessionPhase.transcribing.endsWithTranscription)
        // If a recording (or its start) somehow holds the session, a finishing job leaves it alone.
        XCTAssertFalse(RecordingSessionPhase.recording.endsWithTranscription)
        XCTAssertFalse(RecordingSessionPhase.starting.endsWithTranscription)
    }
}
