public enum ClipboardRestorePolicy {
    public static func shouldRestore(changeCountAfterOurWrite: Int, currentChangeCount: Int) -> Bool {
        changeCountAfterOurWrite == currentChangeCount
    }

    /// Count the hold time from the actual paste event, never from an earlier AX query.
    public static func remainingHoldSeconds(pastedAt: Double, now: Double, minimum: Double) -> Double {
        max(0, minimum - max(0, now - pastedAt))
    }
}
