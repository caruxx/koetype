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

final class RecordingStartDecisionTests: XCTestCase {
    func testACaptureThatCameUpStartsTheRecording() {
        XCTAssertEqual(RecordingStartDecision.decide(outcome: .started, streamStoppedWhileStarting: false), .record)
    }

    func testACaptureThatFailedAborts() {
        XCTAssertEqual(RecordingStartDecision.decide(outcome: .failed, streamStoppedWhileStarting: false), .abortNotPermitted)
    }

    func testACaptureThatNeverCameUpAbortsInsteadOfHoldingTheSession() {
        XCTAssertEqual(RecordingStartDecision.decide(outcome: .timedOut, streamStoppedWhileStarting: false), .abortTimedOut)
        XCTAssertEqual(RecordingStartDecision.timeoutSeconds, 10, accuracy: 0.001)
    }

    func testNoNewRecordingWhileATimedOutStartHasNotReturned() {
        // The old open may still succeed late and close the capture; a newer recording must not be on it.
        XCTAssertFalse(RecordingStartDecision.mayStart(systemStartPending: true))
        XCTAssertTrue(RecordingStartDecision.mayStart(systemStartPending: false))
    }

    func testAStreamThatDiedWhileStartingIsNotRecordedOn() {
        // `onStopped` arrived while the state was still starting: the start is aborted, not continued on
        // a dead stream.
        XCTAssertEqual(RecordingStartDecision.decide(outcome: .started, streamStoppedWhileStarting: true), .abortStreamStopped)
        // A failure or timeout wins over the stream note; nothing was recording anyway.
        XCTAssertEqual(RecordingStartDecision.decide(outcome: .timedOut, streamStoppedWhileStarting: true), .abortTimedOut)
    }
}

final class RecordingStopDecisionTests: XCTestCase {
    func testAStopThatReturnedInTimeIsUsed() {
        XCTAssertEqual(RecordingStopDecision.samples(stopped: [0.1, 0.2], capturedSoFar: [0.1]), [0.1, 0.2])
    }

    func testAStopThatDidNotReturnUsesWhatWasCapturedSoFar() {
        // Nothing is lost: the recording is transcribed and saved from the capture up to the deadline.
        XCTAssertEqual(RecordingStopDecision.samples(stopped: nil, capturedSoFar: [0.3, 0.4, 0.5]), [0.3, 0.4, 0.5])
        XCTAssertEqual(RecordingStopDecision.timeoutSeconds, 5, accuracy: 0.001)
    }
}
