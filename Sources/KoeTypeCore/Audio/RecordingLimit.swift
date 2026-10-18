import Foundation

/// The upper bound of one long recording, measured by elapsed time rather than by captured samples: the
/// microphone may have failed to open, and the Mac's sound alone must still end at the same limit.
/// Elapsed time comes from a monotonic clock, so a wall clock set back can neither delay nor skip it.
public enum RecordingLimit {
    /// True once a recording has run for `maxSeconds`.
    public static func reached(elapsedSeconds: Double, maxSeconds: Double) -> Bool {
        elapsedSeconds >= maxSeconds
    }

    /// How much longer to wait before checking again; never negative.
    public static func remainingSeconds(elapsedSeconds: Double, maxSeconds: Double) -> Double {
        max(0, maxSeconds - elapsedSeconds)
    }
}

/// What the long-recording session may do in each phase. One phase is held at a time, and a phase is
/// claimed before anything is awaited, so a second start or a file job cannot slip in while the first
/// start is still opening its sources.
public enum RecordingSessionPhase: Equatable, Sendable {
    case idle
    /// A start was asked for and its sources are being opened.
    case starting
    case recording
    case transcribing

    /// A recording or a file transcription may begin only from idle.
    public var acceptsStart: Bool { self == .idle }
    /// Only a running recording can be stopped; a start still opening its sources is left to finish or fail.
    public var acceptsStop: Bool { self == .recording }
    /// The end of a transcription job returns the session to idle only while it is the one transcribing:
    /// it must never end a recording or a start that began in the meantime.
    public var endsWithTranscription: Bool { self == .transcribing }
}

/// What the session does once opening the Mac's sound has come to an end, one way or another. The open
/// is bounded: a capture that never comes up must not hold the session in its starting phase for good.
public enum RecordingStartDecision: Equatable, Sendable {
    /// How long opening the Mac's sound may take before the start is given up.
    public static let timeoutSeconds: Double = 10

    public enum Outcome: Equatable, Sendable {
        case started
        case failed
        /// Nothing was heard back within `timeoutSeconds`.
        case timedOut
    }

    case record
    /// Abort: the capture could not be opened (permission or no display).
    case abortNotPermitted
    /// Abort: the capture did not come up in time; a late success is torn down, not used.
    case abortTimedOut
    /// Abort: the capture came up but its stream had already died while it was starting.
    case abortStreamStopped

    /// Whether a new recording may be started: not while a start that was given up on has still not
    /// returned. The one shared capture cannot be opened twice, and when the old open does return its
    /// teardown must find no newer recording using the capture. A file transcription does not use the
    /// capture and is not held back by this.
    public static func mayStart(systemStartPending: Bool) -> Bool {
        !systemStartPending
    }

    public static func decide(outcome: Outcome, streamStoppedWhileStarting: Bool) -> RecordingStartDecision {
        switch outcome {
        case .failed: return .abortNotPermitted
        case .timedOut: return .abortTimedOut
        case .started: return streamStoppedWhileStarting ? .abortStreamStopped : .record
        }
    }
}

/// How a stop of the Mac's sound that does not return is handled: the recording goes on to be
/// transcribed and saved with what was captured, rather than waiting for good.
public enum RecordingStopDecision {
    /// How long closing the Mac's sound may take before what was captured so far is used instead.
    public static let timeoutSeconds: Double = 5

    /// The samples to transcribe: the stop's own result when it returned in time, else the capture so far.
    public static func samples(stopped: [Float]?, capturedSoFar: [Float]) -> [Float] {
        stopped ?? capturedSoFar
    }
}
