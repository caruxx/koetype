import Foundation

/// A result awaited for at most a deadline. Whichever comes first, the result or the deadline, is what
/// the caller gets; the other side is dropped instead of being waited for, so a producer that never
/// calls back (a Core Audio query that stalls) cannot hold the caller.
public enum Deadline {
    /// Calls `produce` with a completion that may be called once, late, or never, and returns the value
    /// it delivers unless `seconds` pass first.
    public static func first<Value: Sendable>(within seconds: TimeInterval, on queue: DispatchQueue = .global(),
                                              produce: (@escaping @Sendable (Value) -> Void) -> Void) async -> Value? {
        await withCheckedContinuation { (continuation: CheckedContinuation<Value?, Never>) in
            let claim = FirstClaim()
            produce { value in
                if claim.take() { continuation.resume(returning: value) }
            }
            queue.asyncAfter(deadline: .now() + seconds) {
                if claim.take() { continuation.resume(returning: nil) }
            }
        }
    }
}

/// Settles which of two sides got somewhere first; every later attempt is refused.
public final class FirstClaim: @unchecked Sendable {
    private let lock = NSLock()
    private var taken = false

    public init() {}

    /// True for the first call only.
    public func take() -> Bool {
        lock.withLock {
            defer { taken = true }
            return !taken
        }
    }
}
