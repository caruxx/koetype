import Foundation

/// The current session's most recent delivery, independent of history persistence.
/// Keep only one text in memory; never write it to a diagnostic log.
public final class LatestDeliveryMemory: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String?

    public init() {}

    public var latestText: String? { lock.withLock { stored } }

    public func remember(_ text: String) {
        lock.withLock { stored = text }
    }
}
