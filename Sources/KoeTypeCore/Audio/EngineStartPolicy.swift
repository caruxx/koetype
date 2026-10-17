import Foundation

/// Decides when a microphone that does not answer is given up on, and whether an engine whose start
/// finishes late may still be used. Core Audio can stall for a very long time (Bluetooth profile
/// switches, Continuity microphones), so every stretch of work that can block, a start as well as the
/// handling of a configuration change, is numbered and watched from outside; it is never waited for.
public enum EngineStartPolicy {
    /// How long a stretch of work may take, and how long a started engine may stay silent, before the
    /// microphone is treated as not responding.
    public static let timeout: TimeInterval = 3

    /// True when the numbered `work`, begun for recording `generation`, is still the current recording's
    /// and has not reported back: the recorder gives up on it. Work for an older recording is left alone,
    /// because the newer recording's own work sits behind it on the same queue and is watched by itself.
    /// Work is tracked one by one, not by the highest number reported: numbers are handed out from
    /// several threads and can be begun and finished out of order.
    /// - Parameters:
    ///   - work: the number of the stretch of work.
    ///   - generation: the recording the work was begun for.
    ///   - current: the generation of the latest recording.
    ///   - pending: the work numbers that have neither reported back nor been given up on.
    public static func givesUp(work: Int, generation: Int, current: Int, pending: Set<Int>) -> Bool {
        generation == current && pending.contains(work)
    }

    /// True when a silence watch may be armed by a (re)start that just succeeded: only the worker in use,
    /// not given up on, and only for the recording that is current. A late report from a worker already
    /// replaced must not overwrite the watch of the recording now running.
    public static func armsSilenceWatch(workerCurrent: Bool, abandoned: Bool, generation: Int, current: Int) -> Bool {
        workerCurrent && !abandoned && generation == current
    }

    /// What a silence watch does when it fires.
    public enum SilenceVerdict: Equatable {
        /// Nothing: the microphone was heard, or the recording is over or no longer current.
        case keep
        /// The microphone is treated as not responding and the worker is given up on.
        case giveUp
        /// Nothing has been heard, but a configuration change is still being handled: ask again after
        /// another `timeout`. A restart that succeeds meanwhile arms a newer watch, which replaces this one.
        case checkAgain
    }

    /// Judges a recording whose engine reported (re)started, `timeout` after that (re)start. Only a
    /// recording that is still running and still current counts; a short tap or a newer recording is
    /// not judged. Nothing heard means the worker is given up on, unless a configuration change is still
    /// being handled: from the moment it is noted (the device query before any restart can itself take a
    /// while) until its handling is over, including a restart chain it begins (an attempt running or a
    /// retry waiting its backoff), silence is expected. A stuck step is bounded by its own work watchdog
    /// and the retries are counted; the verdict is only put off, so a change that ends without a restart
    /// still has the silence judged afterwards.
    /// - Parameters:
    ///   - changePending: a configuration change of this recording is noted and not yet fully handled.
    public static func silenceVerdict(generation: Int, current: Int, recording: Bool, audioHeard: Bool,
                                      changePending: Bool) -> SilenceVerdict {
        guard generation == current, recording, !audioHeard else { return .keep }
        return changePending ? .checkAgain : .giveUp
    }

    /// True when an engine whose start just finished is kept. Only an engine the recorder gave up on is
    /// stopped: it must never feed a newer recording. An engine that came up for a recording that has
    /// already ended (a short tap, or a second press before the microphone opened) is kept all the same,
    /// so the keep-open and reuse paths get it instead of opening the microphone again; what is captured
    /// is gated by the recorder, not by the engine.
    public static func acceptsEngine(abandoned: Bool) -> Bool {
        !abandoned
    }
}
