import Foundation

/// Decides when a microphone that has not come up is given up on, and whether an engine whose start
/// finishes late may still be used. Core Audio can stall for a very long time (Bluetooth profile
/// switches, Continuity microphones), so a start is watched from outside and never waited for.
public enum EngineStartPolicy {
    /// How long a start may take before the microphone is treated as not responding.
    public static let timeout: TimeInterval = 3

    /// True when the start made for recording `started` is still the current recording and has
    /// not reported back (success or failure): the recorder gives up on it.
    /// - Parameters:
    ///   - started: the recording generation the start was made for.
    ///   - current: the generation of the latest recording.
    ///   - lastCompleted: the newest generation whose start has reported back.
    public static func givesUp(started: Int, current: Int, lastCompleted: Int) -> Bool {
        started == current && lastCompleted < started
    }

    /// True when an engine whose start just finished may deliver audio. An engine the recorder gave up
    /// on, or one made for an older recording, is stopped instead: it must never feed a newer recording.
    public static func acceptsEngine(abandoned: Bool, started: Int, current: Int) -> Bool {
        !abandoned && started == current
    }
}
