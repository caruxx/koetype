import XCTest
@testable import KoeTypeCore

final class InsertionDecisionTests: XCTestCase {
    private func snapshot(role: String?, range: Bool = false, editable: Bool = false, length: Int? = nil) -> FocusSnapshot {
        FocusSnapshot(role: role, hasSelectedTextRange: range, isEditable: editable, valueLength: length)
    }

    func testFailedQueryPastesAndShowsTheCopyBox() {
        XCTAssertEqual(InsertionDecision.plan(for: nil), .pasteAndCopyBox)
    }

    func testSystemWideFocusedElementMustBelongToFrontmostApp() {
        XCTAssertTrue(InsertionDecision.isOwnedByFrontmostApp(frontmostPID: 10, targetPID: 10))
        XCTAssertFalse(InsertionDecision.isOwnedByFrontmostApp(frontmostPID: 10, targetPID: 11))
        XCTAssertFalse(InsertionDecision.isOwnedByFrontmostApp(frontmostPID: 10, targetPID: nil))
        XCTAssertTrue(InsertionDecision.isSameApplication(originalPID: 10, currentPID: 10))
        XCTAssertFalse(InsertionDecision.isSameApplication(originalPID: nil, currentPID: nil))
        XCTAssertFalse(InsertionDecision.isSameApplication(originalPID: 10, currentPID: nil))
    }

    func testNoFocusedElementAndNoWindowShowsCopyBoxOnly() {
        XCTAssertEqual(InsertionDecision.plan(for: snapshot(role: nil)), .copyBoxOnly)
    }

    func testAppThatHidesItsFocusStillGetsThePaste() {
        // Measured in the ChatGPT app: with the cursor in the message field, 10 of 26 queries
        // answered "no focused element". Showing only the copy box lost the insertion.
        let hidden = FocusSnapshot(role: nil, hasSelectedTextRange: false, appHasFocusedWindow: true)
        XCTAssertEqual(InsertionDecision.plan(for: hidden), .pasteAndCopyBox)
    }

    func testReadableTextValueIsPastedAndThenVerified() {
        XCTAssertEqual(InsertionDecision.plan(for: snapshot(role: "AXTextArea", range: true, editable: true, length: 12)),
                       .pasteThenVerify)
        XCTAssertEqual(InsertionDecision.plan(for: snapshot(role: "AXTextField", length: 0)), .pasteAndCopyBox)
    }

    func testSelectedTextRangeAloneNoLongerMeansAnInputField() {
        // Measured: a web page body reports a selected text range although nothing can be typed there.
        // Before this was treated as an input field, so the text vanished and no copy box appeared.
        XCTAssertEqual(InsertionDecision.plan(for: snapshot(role: "AXWebArea", range: true)), .pasteAndCopyBox)
        XCTAssertEqual(InsertionDecision.plan(for: snapshot(role: "AXWebArea", range: true, length: 0)), .pasteAndCopyBox)
        XCTAssertEqual(InsertionDecision.plan(for: snapshot(role: "AXGroup", range: true, length: 0)), .pasteAndCopyBox)
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
        XCTAssertEqual(InsertionDecision.plan(for: snapshot(role: "AXScrollArea", editable: true, length: 3)), .pasteOnly)
    }

    func testUnknownElementPastesAndShowsTheCopyBox() {
        XCTAssertEqual(InsertionDecision.plan(for: snapshot(role: "AXGroup")), .pasteAndCopyBox)
        XCTAssertEqual(InsertionDecision.plan(for: snapshot(role: "AXTextArea")), .pasteAndCopyBox)
    }

    func testSelectionBasedVerificationRejectsUnrelatedEditsAroundExistingText() {
        XCTAssertFalse(InsertionDecision.didInsert(
            valueBefore: "a new b", valueAfter: "x new y", insertedText: "new",
            selection: InsertionSelection(location: 0, length: 1)))
        XCTAssertFalse(InsertionDecision.didInsert(
            valueBefore: "old new", valueAfter: "old new!", insertedText: "new",
            selection: InsertionSelection(location: 7, length: 0)))
    }

    func testSelectionBasedVerificationAcceptsSameLengthWholeFieldReplacement() {
        XCTAssertTrue(InsertionDecision.didInsert(
            valueBefore: "hello", valueAfter: "hallo", insertedText: "hallo",
            selection: InsertionSelection(location: 0, length: 5)))
        XCTAssertTrue(InsertionDecision.didInsert(
            valueBefore: "hello", valueAfter: "jello", insertedText: "j",
            selection: InsertionSelection(location: 0, length: 1)))
    }

    func testUnknownOrInvalidSelectionCannotConfirmInsertion() {
        XCTAssertFalse(InsertionDecision.didInsert(
            valueBefore: "hello", valueAfter: "helloj", insertedText: "j", selection: nil))
        XCTAssertFalse(InsertionDecision.didInsert(
            valueBefore: "hello", valueAfter: "helloj", insertedText: "j",
            selection: InsertionSelection(location: 99, length: 0)))
        XCTAssertFalse(InsertionDecision.didInsert(
            valueBefore: "hello", valueAfter: nil, insertedText: "j",
            selection: InsertionSelection(location: 5, length: 0)))
        XCTAssertFalse(InsertionDecision.didInsert(
            valueBefore: "hello", valueAfter: "hello", insertedText: "hello",
            selection: InsertionSelection(location: 0, length: 5)))
    }

    func testVerificationUsesUTF16RangeAndCanonicalNormalization() {
        XCTAssertTrue(InsertionDecision.didInsert(
            valueBefore: "🙂a", valueAfter: "🙂e\u{301}", insertedText: "é",
            selection: InsertionSelection(location: 2, length: 1)))
    }
}
