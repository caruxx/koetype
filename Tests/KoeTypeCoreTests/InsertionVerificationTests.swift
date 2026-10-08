import XCTest
@testable import KoeTypeCore

@MainActor final class InsertionVerificationTests: XCTestCase {
    private let caret = InsertionSelection(location: 5, length: 0)

    private func field(_ value: String?, selection: InsertionSelection? = nil,
                       sameApp: Bool = true, sameElement: Bool = true,
                       role: String = "AXTextArea", editable: Bool = true) -> InsertionVerification.Sample {
        .field(value: value, selection: selection, sameApp: sameApp,
               sameElement: sameElement,
               snapshot: FocusSnapshot(role: role, hasSelectedTextRange: true,
                                       isEditable: editable, valueLength: value?.count))
    }

    func testDelayedRenderConfirmsAfterExactlyOnePaste() async {
        var pastes = 0
        var samples = 0
        let result = await InsertionVerification.pasteAndVerify(
            valueBefore: "draft", selection: caret, insertedText: "new",
            attempts: 3, intervalNanoseconds: 0,
            paste: { pastes += 1; return true }, observe: {
                samples += 1
                return self.field(samples < 4 ? "draft" : "draftnew", selection: self.caret)
            })
        XCTAssertEqual(result, .init(result: .confirmed, didPaste: true))
        XCTAssertEqual(pastes, 1)
        XCTAssertEqual(samples, 4) // preflight, two stale values, then rendered text
    }

    func testPreflightRejectsAnotherAppBeforePasting() async {
        var pastes = 0
        let result = await InsertionVerification.pasteAndVerify(
            valueBefore: "draft", selection: caret, insertedText: "new", intervalNanoseconds: 0,
            paste: { pastes += 1; return true }, observe: { self.field("draft", selection: self.caret, sameApp: false) })
        XCTAssertEqual(result, .init(result: .targetChanged, didPaste: false))
        XCTAssertEqual(pastes, 0)
    }

    func testElementOrRoleChangeAfterPasteCannotConfirmOrRepaste() async {
        for changed in [field("draftnew", sameElement: false), field("draftnew", role: "AXGroup"),
                        field("draftnew", editable: false)] {
            var pastes = 0
            var samples = 0
            let result = await InsertionVerification.pasteAndVerify(
                valueBefore: "draft", selection: caret, insertedText: "new", intervalNanoseconds: 0,
                paste: { pastes += 1; return true }, observe: {
                    samples += 1
                    return samples == 1 ? self.field("draft", selection: self.caret) : changed
                })
            XCTAssertEqual(result, .init(result: .targetChanged, didPaste: true))
            XCTAssertEqual(pastes, 1)
        }
    }

    func testChangedSelectionBeforePasteStaysUnverifiedWithoutPasting() async {
        var pastes = 0
        let result = await InsertionVerification.pasteAndVerify(
            valueBefore: "draft", selection: caret, insertedText: "new", intervalNanoseconds: 0,
            paste: { pastes += 1; return true }, observe: {
                self.field("draft", selection: InsertionSelection(location: 0, length: 5))
            })
        XCTAssertEqual(result, .init(result: .unverified, didPaste: false))
        XCTAssertEqual(pastes, 0)
    }

    func testSameLengthWholeFieldReplacementCanBeConfirmed() async {
        let all = InsertionSelection(location: 0, length: 5)
        var samples = 0
        let result = await InsertionVerification.pasteAndVerify(
            valueBefore: "hello", selection: all, insertedText: "hallo", attempts: 1,
            intervalNanoseconds: 0, paste: { true }, observe: {
                samples += 1
                return self.field(samples == 1 ? "hello" : "hallo", selection: all)
            })
        XCTAssertEqual(result, .init(result: .confirmed, didPaste: true))
    }

    func testSubmittedAndClearedFieldRemainsUnverifiedWithoutRepasting() async {
        var pastes = 0
        var samples = 0
        let result = await InsertionVerification.pasteAndVerify(
            valueBefore: "draft", selection: caret, insertedText: "new", attempts: 2,
            intervalNanoseconds: 0, paste: { pastes += 1; return true }, observe: {
                samples += 1
                return self.field(samples == 1 ? "draft" : "", selection: self.caret)
            })
        XCTAssertEqual(result, .init(result: .unverified, didPaste: true))
        XCTAssertEqual(pastes, 1)
    }

    func testUnavailableFieldRemainsUnverifiedWithoutRetryingPaste() async {
        var pastes = 0
        var samples = 0
        let result = await InsertionVerification.pasteAndVerify(
            valueBefore: "draft", selection: caret, insertedText: "new", attempts: 3,
            intervalNanoseconds: 0, paste: { pastes += 1; return true }, observe: {
                samples += 1
                return samples == 1 ? self.field("draft", selection: self.caret) : .temporarilyUnavailable
            })
        XCTAssertEqual(result, .init(result: .unverified, didPaste: true))
        XCTAssertEqual(pastes, 1)
    }

    func testDispatchFailureDoesNotClaimPasteOrRetry() async {
        var attempts = 0
        let result = await InsertionVerification.pasteAndVerify(
            valueBefore: "draft", selection: caret, insertedText: "new", intervalNanoseconds: 0,
            paste: { attempts += 1; return false },
            observe: { self.field("draft", selection: self.caret) })
        XCTAssertEqual(result, .init(result: .dispatchFailed, didPaste: false))
        XCTAssertEqual(attempts, 1)
    }
}
