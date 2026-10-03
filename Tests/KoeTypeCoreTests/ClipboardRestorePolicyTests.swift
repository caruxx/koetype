import XCTest
@testable import KoeTypeCore

final class ClipboardRestorePolicyTests: XCTestCase {
    func testRestoresWhenNothingElseTouchedTheClipboard() {
        XCTAssertTrue(ClipboardRestorePolicy.shouldRestore(changeCountAfterOurWrite: 42, currentChangeCount: 42))
    }

    func testDoesNotClobberANewerCopyByTheUser() {
        XCTAssertFalse(ClipboardRestorePolicy.shouldRestore(changeCountAfterOurWrite: 42, currentChangeCount: 43))
    }
}
