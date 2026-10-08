import Foundation

/// UTF-16 offsets, matching the AXSelectedTextRange CFRange.
public struct InsertionSelection: Equatable, Sendable {
    public let location: Int
    public let length: Int

    public init(location: Int, length: Int) {
        self.location = location
        self.length = length
    }
}

/// What the accessibility API reports about the element that has keyboard focus.
public struct FocusSnapshot: Equatable, Sendable {
    /// AXRole of the focused element; nil when nothing has focus.
    public var role: String?
    public var hasSelectedTextRange: Bool
    /// The element accepts typed text (its value or selection can be set).
    public var isEditable: Bool
    /// Number of characters currently in the element, when it can be read.
    public var valueLength: Int?
    /// The frontmost app has a focused window, even if it does not say which element in it has focus.
    public var appHasFocusedWindow: Bool

    public init(role: String?, hasSelectedTextRange: Bool, isEditable: Bool = false, valueLength: Int? = nil,
                appHasFocusedWindow: Bool = false) {
        self.role = role; self.hasSelectedTextRange = hasSelectedTextRange
        self.isEditable = isEditable; self.valueLength = valueLength
        self.appHasFocusedWindow = appHasFocusedWindow
    }
}

public enum InsertionPlan: Equatable, Sendable {
    /// Paste and trust it.
    case pasteOnly
    /// Paste, then confirm the field's content changed; show the copy box if it did not.
    case pasteThenVerify
    /// Nothing can receive text: show the copy box.
    case copyBoxOnly
    /// Cannot tell: paste and also show the copy box.
    case pasteAndCopyBox
}

public enum InsertionDecision {
    static let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]
    static let nonTextRoles: Set<String> = [
        "AXButton", "AXImage", "AXList", "AXOutline", "AXTable", "AXScrollArea",
        "AXMenuItem", "AXMenuBarItem", "AXCheckBox", "AXRadioButton", "AXToolbar",
    ]

    /// `snapshot` is nil when the accessibility query itself failed.
    public static func plan(for snapshot: FocusSnapshot?) -> InsertionPlan {
        guard let snapshot else { return .pasteAndCopyBox }
        guard let role = snapshot.role else {
            // Some apps (Electron, web views) do not report their focused element reliably.
            // With a window in front the cursor may well be in a text field, so paste anyway
            // and keep the copy box as the safety net.
            return snapshot.appHasFocusedWindow ? .pasteAndCopyBox : .copyBoxOnly
        }
        // A parent AXGroup (or web page body) can expose a selection and a readable
        // value without representing the actual editable field.
        if canVerify(snapshot) { return .pasteThenVerify }
        if snapshot.isEditable { return .pasteOnly }
        if nonTextRoles.contains(role) { return .copyBoxOnly }
        return .pasteAndCopyBox
    }

    public static func canVerify(_ snapshot: FocusSnapshot) -> Bool {
        guard let role = snapshot.role else { return false }
        return textRoles.contains(role) && snapshot.isEditable && snapshot.hasSelectedTextRange
            && snapshot.valueLength != nil
    }

    public static func isOwnedByFrontmostApp(frontmostPID: Int32, targetPID: Int32?) -> Bool {
        targetPID == frontmostPID
    }

    public static func isSameApplication(originalPID: Int32?, currentPID: Int32?) -> Bool {
        guard let originalPID, let currentPID else { return false }
        return originalPID == currentPID
    }

    /// Confirm only the exact replacement at the selection captured before the paste.
    /// An unknown or invalid range cannot prove where the text landed.
    public static func didInsert(valueBefore: String, valueAfter: String?, insertedText: String,
                                 selection: InsertionSelection?) -> Bool {
        guard let valueAfter, let selection, !insertedText.isEmpty else { return false }
        let old = valueBefore as NSString
        guard selection.location >= 0, selection.length >= 0,
              selection.location <= old.length,
              selection.length <= old.length - selection.location else { return false }
        let expected = old.replacingCharacters(
            in: NSRange(location: selection.location, length: selection.length), with: insertedText)
        let normalizedAfter = valueAfter.precomposedStringWithCanonicalMapping
        return normalizedAfter != valueBefore.precomposedStringWithCanonicalMapping
            && normalizedAfter == expected.precomposedStringWithCanonicalMapping
    }
}
