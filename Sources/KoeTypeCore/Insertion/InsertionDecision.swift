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
        let looksLikeText = snapshot.isEditable || snapshot.hasSelectedTextRange || textRoles.contains(role)
        // A readable value is the only way to know afterwards whether the paste landed.
        if looksLikeText, snapshot.valueLength != nil { return .pasteThenVerify }
        if snapshot.isEditable { return .pasteOnly }
        if nonTextRoles.contains(role) { return .copyBoxOnly }
        return .pasteAndCopyBox
    }

    /// The paste reached the field if its content length is different afterwards.
    public static func didInsert(lengthBefore: Int, lengthAfter: Int?) -> Bool {
        guard let lengthAfter else { return false }
        return lengthAfter != lengthBefore
    }
}
