public enum ClipboardRestorePolicy {
    public static func shouldRestore(changeCountAfterOurWrite: Int, currentChangeCount: Int) -> Bool {
        changeCountAfterOurWrite == currentChangeCount
    }
}
