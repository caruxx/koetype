import Foundation

/// Callers waiting for one shared result that is still on its way, each only until its own deadline.
/// A caller whose deadline has passed has already been answered without the result (see `Deadline`), so
/// it is dropped the next time someone is added; one still waiting is never dropped. That keeps the list
/// as short as the callers actually waiting, however long the result takes.
public struct SharedWaiters<Waiter> {
    private var waiting: [(deadline: UInt64, waiter: Waiter)] = []
    private var inFlight = false

    public init() {}

    /// The callers still kept, expired or not.
    public var count: Int { waiting.count }

    /// Adds a caller that waits until `deadline` (both times in `DispatchTime.uptimeNanoseconds`).
    /// Returns true when no result is on its way: this caller has to ask for one.
    public mutating func add(_ waiter: Waiter, deadline: UInt64, now: UInt64) -> Bool {
        waiting.removeAll { $0.deadline <= now }
        waiting.append((deadline, waiter))
        defer { inFlight = true }
        return !inFlight
    }

    /// The result arrived: every caller kept gets it (one already answered ignores it), and the next
    /// caller asks again.
    public mutating func takeAll() -> [Waiter] {
        inFlight = false
        defer { waiting.removeAll() }
        return waiting.map(\.waiter)
    }
}
