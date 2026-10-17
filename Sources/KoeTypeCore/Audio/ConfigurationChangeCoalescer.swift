import Foundation

/// Folds a burst of configuration changes (a Bluetooth profile switch posts several) into one handling
/// at a time plus at most one follow-up, without losing track of which recordings are waiting on them.
///
/// Every arrival is counted as pending for the recording current when it arrived (silence is not judged
/// meanwhile), and each count is handed on until the handling that covers it is over: the one queued
/// now, or the follow-up, or released at once when no follow-up is needed. A count is never dropped, so
/// a change that arrives for a newer recording while an older one's handling runs still holds that
/// newer recording's silence verdict.
public struct ConfigurationChangeCoalescer<Source: AnyObject> {
    /// A handling to queue: for `generation`, covering the arrivals counted for `counted`.
    public struct Handling: Equatable {
        public let generation: Int
        public let counted: [Int]
    }

    private struct WeakSource {
        weak var source: Source?
    }

    private var busy = false
    /// Arrivals while busy: the generation of the latest, the sources they came from, and their counts.
    private var again: (generation: Int, sources: [WeakSource], counted: [Int])?

    public init() {}

    /// A change from `source` arrived for recording `generation`, already counted for each of
    /// `counted`. Returns the handling to queue now, or nil when one is queued or running: the arrival is
    /// then folded into its follow-up (the latest arrival's generation wins).
    public mutating func arrive(generation: Int, counted: [Int], from source: Source) -> Handling? {
        guard busy else {
            busy = true
            return Handling(generation: generation, counted: counted)
        }
        var sources = again?.sources.filter { $0.source != nil } ?? []
        if !sources.contains(where: { $0.source === source }) { sources.append(WeakSource(source: source)) }
        again = (generation, sources, (again?.counted ?? []) + counted)
        return nil
    }

    /// The handling is over. Changes that arrived meanwhile are handled once more for `current`, the
    /// source in use now, if they came from it: one replaced meanwhile has no business being handled, and
    /// a change of the one that replaced it is not lost. Otherwise their counts are released. A follow-up
    /// is handed over still busy, to be queued by the caller as it is: an arrival in between is folded
    /// into the follow-up's own follow-up and cannot overwrite its generation.
    public mutating func finish(current: Source?) -> (followUp: Handling?, released: [Int]) {
        defer { again = nil }
        guard let again, let current, again.sources.contains(where: { $0.source === current }) else {
            busy = false
            return (nil, again?.counted ?? [])
        }
        return (Handling(generation: again.generation, counted: again.counted), [])
    }
}
