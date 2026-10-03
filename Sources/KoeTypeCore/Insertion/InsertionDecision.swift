public struct FocusSnapshot: Equatable, Sendable {
    public var role: String?
    public var hasSelectedTextRange: Bool
    public init(role: String?, hasSelectedTextRange: Bool) {
        self.role = role; self.hasSelectedTextRange = hasSelectedTextRange
    }
}

public enum InsertionPlan: Equatable, Sendable { case pasteOnly, copyBoxOnly, pasteAndCopyBox }

public enum InsertionDecision {
    static let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]
    static let nonTextRoles: Set<String> = [
        "AXButton", "AXImage", "AXList", "AXOutline", "AXTable", "AXScrollArea",
        "AXMenuItem", "AXMenuBarItem", "AXCheckBox", "AXRadioButton", "AXToolbar",
    ]

    public static func plan(for snapshot: FocusSnapshot?) -> InsertionPlan {
        guard let snapshot else { return .pasteAndCopyBox }
        if snapshot.hasSelectedTextRange { return .pasteOnly }
        guard let role = snapshot.role else { return .copyBoxOnly }
        if textRoles.contains(role) { return .pasteOnly }
        if nonTextRoles.contains(role) { return .copyBoxOnly }
        return .pasteAndCopyBox
    }
}
