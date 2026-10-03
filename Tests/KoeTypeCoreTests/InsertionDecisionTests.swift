import XCTest
@testable import KoeTypeCore

final class InsertionDecisionTests: XCTestCase {
    private func snapshot(role: String?, range: Bool = false, editable: Bool = false, length: Int? = nil) -> FocusSnapshot {
        FocusSnapshot(role: role, hasSelectedTextRange: range, isEditable: editable, valueLength: length)
    }

    func testFailedQueryPastesAndShowsTheCopyBox() {
        XCTAssertEqual(InsertionDecision.plan(for: nil), .pasteAndCopyBox)
    }

    func testNoFocusedElementShowsCopyBoxOnly() {
        XCTAssertEqual(InsertionDecision.plan(for: snapshot(role: nil)), .copyBoxOnly)
    }

    func testReadableTextValueIsPastedAndThenVerified() {
        XCTAssertEqual(InsertionDecision.plan(for: snapshot(role: "AXTextArea", range: true, editable: true, length: 12)),
                       .pasteThenVerify)
        XCTAssertEqual(InsertionDecision.plan(for: snapshot(role: "AXTextField", length: 0)), .pasteThenVerify)
    }

    func testSelectedTextRangeAloneNoLongerMeansAnInputField() {
        // Measured: a web page body reports a selected text range although nothing can be typed there.
        // Before this was treated as an input field, so the text vanished and no copy box appeared.
        XCTAssertEqual(InsertionDecision.plan(for: snapshot(role: "AXWebArea", range: true)), .pasteAndCopyBox)
        XCTAssertEqual(InsertionDecision.plan(for: snapshot(role: "AXWebArea", range: true, length: 0)), .pasteThenVerify)
    }

    func testEditableWithoutReadableValueIsTrusted() {
        XCTAssertEqual(InsertionDecision.plan(for: snapshot(role: "AXGroup", editable: true)), .pasteOnly)
    }

    func testKnownNonTextRolesShowCopyBoxOnly() {
        for role in ["AXButton", "AXImage", "AXList", "AXOutline", "AXTable", "AXScrollArea",
                     "AXMenuItem", "AXMenuBarItem", "AXCheckBox", "AXRadioButton", "AXToolbar"] {
            XCTAssertEqual(InsertionDecision.plan(for: snapshot(role: role)), .copyBoxOnly, role)
        }
    }

    func testEditableElementWinsOverANonTextRole() {
        XCTAssertEqual(InsertionDecision.plan(for: snapshot(role: "AXScrollArea", editable: true, length: 3)), .pasteThenVerify)
    }

    func testUnknownElementPastesAndShowsTheCopyBox() {
        XCTAssertEqual(InsertionDecision.plan(for: snapshot(role: "AXGroup")), .pasteAndCopyBox)
        XCTAssertEqual(InsertionDecision.plan(for: snapshot(role: "AXTextArea")), .pasteAndCopyBox)
    }

    func testPasteCountsAsInsertedOnlyWhenTheFieldChanged() {
        XCTAssertTrue(InsertionDecision.didInsert(lengthBefore: 10, lengthAfter: 25))
        XCTAssertTrue(InsertionDecision.didInsert(lengthBefore: 30, lengthAfter: 12))   // replaced a selection
        XCTAssertFalse(InsertionDecision.didInsert(lengthBefore: 10, lengthAfter: 10))
        XCTAssertFalse(InsertionDecision.didInsert(lengthBefore: 10, lengthAfter: nil))
    }
}
