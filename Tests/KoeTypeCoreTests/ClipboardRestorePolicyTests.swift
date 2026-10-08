import XCTest
@testable import KoeTypeCore

final class ClipboardRestorePolicyTests: XCTestCase {
    func testRestoresWhenNothingElseTouchedTheClipboard() {
        XCTAssertTrue(ClipboardRestorePolicy.shouldRestore(changeCountAfterOurWrite: 42, currentChangeCount: 42))
    }

    func testDoesNotClobberANewerCopyByTheUser() {
        XCTAssertFalse(ClipboardRestorePolicy.shouldRestore(changeCountAfterOurWrite: 42, currentChangeCount: 43))
    }

    func testHoldTimeStartsAtPasteEvenAfterSlowFocusInspection() {
        XCTAssertEqual(ClipboardRestorePolicy.remainingHoldSeconds(
            pastedAt: 200, now: 200.1, minimum: 0.8), 0.7, accuracy: 0.0001)
        XCTAssertEqual(ClipboardRestorePolicy.remainingHoldSeconds(
            pastedAt: 200, now: 201.2, minimum: 0.8), 0, accuracy: 0.0001)
    }
}
