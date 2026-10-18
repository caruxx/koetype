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
