import XCTest
@testable import KoeTypeCore

final class InsertionDecisionTests: XCTestCase {
    func testTextRolesPasteOnly() {
        for role in ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"] {
            XCTAssertEqual(InsertionDecision.plan(for: FocusSnapshot(role: role, hasSelectedTextRange: false)), .pasteOnly)
        }
    }

    func testAnyElementWithSelectedTextRangePastesOnly() {
        XCTAssertEqual(InsertionDecision.plan(for: FocusSnapshot(role: "AXWebArea", hasSelectedTextRange: true)), .pasteOnly)
    }

    func testNoFocusedElementShowsCopyBoxOnly() {
        XCTAssertEqual(InsertionDecision.plan(for: FocusSnapshot(role: nil, hasSelectedTextRange: false)), .copyBoxOnly)
    }

    func testKnownNonTextRolesShowCopyBoxOnly() {
        for role in ["AXButton", "AXImage", "AXList", "AXOutline", "AXTable", "AXScrollArea",
                     "AXMenuItem", "AXMenuBarItem", "AXCheckBox", "AXRadioButton", "AXToolbar"] {
            XCTAssertEqual(InsertionDecision.plan(for: FocusSnapshot(role: role, hasSelectedTextRange: false)), .copyBoxOnly)
        }
    }

    func testUnknownRoleOrFailedQueryDoesBoth() {
        XCTAssertEqual(InsertionDecision.plan(for: FocusSnapshot(role: "AXGroup", hasSelectedTextRange: false)), .pasteAndCopyBox)
        XCTAssertEqual(InsertionDecision.plan(for: FocusSnapshot(role: "AXWebArea", hasSelectedTextRange: false)), .pasteAndCopyBox)
        XCTAssertEqual(InsertionDecision.plan(for: nil), .pasteAndCopyBox)
    }
}
