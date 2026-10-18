import Foundation

/// The upper bound of one long recording, measured by the clock rather than by captured samples: the
/// microphone may have failed to open, and the Mac's sound alone must still end at the same limit.
public enum RecordingLimit {
    /// True once the recording that began at `startedAt` has run for `maxSeconds`.
    public static func reached(startedAt: Date, now: Date, maxSeconds: Double) -> Bool {
        now.timeIntervalSince(startedAt) >= maxSeconds
    }
}
