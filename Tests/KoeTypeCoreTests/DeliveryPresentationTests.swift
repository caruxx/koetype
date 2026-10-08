import XCTest
@testable import KoeTypeCore

final class DeliveryPresentationTests: XCTestCase {
    func testVerifiedInsertionHasNoPopupOrWarning() {
        XCTAssertEqual(DeliveryPresentation.outcome(plan: .pasteThenVerify, didPaste: true,
                                                    verification: .confirmed), .inserted)
        XCTAssertNil(DeliveryPresentation.copyBoxMessage(outcome: .inserted, verification: .confirmed))
        XCTAssertNil(DeliveryPresentation.indicatorMessage(outcome: .inserted))
    }

    func testRepeatedUnknownFocusNeverShowsCopyPopupOrClaimsSuccess() {
        let focus = FocusSnapshot(role: nil, hasSelectedTextRange: false, appHasFocusedWindow: true)
        for _ in 0..<4 {
            XCTAssertEqual(InsertionDecision.plan(for: focus), .pasteAndCopyBox)
            XCTAssertEqual(DeliveryPresentation.outcome(plan: .pasteAndCopyBox, didPaste: true,
                                                        verification: nil), .unverified)
            XCTAssertNil(DeliveryPresentation.copyBoxMessage(outcome: .unverified, verification: nil))
            XCTAssertEqual(DeliveryPresentation.indicatorMessage(outcome: .unverified), "入力未確認")
        }
    }

    func testPreflightChangeIsNotPastedWithoutPopup() {
        XCTAssertEqual(DeliveryPresentation.outcome(plan: .pasteThenVerify, didPaste: false,
                                                    verification: .targetChanged), .notPasted)
        XCTAssertNil(DeliveryPresentation.copyBoxMessage(outcome: .notPasted, verification: .targetChanged))
        XCTAssertEqual(DeliveryPresentation.indicatorMessage(outcome: .notPasted),
                       "貼り付けませんでした。メニューからコピーできます")
    }

    func testEventCreationFailureOffersCopyWithReason() {
        XCTAssertEqual(DeliveryPresentation.outcome(plan: .pasteAndCopyBox, didPaste: false,
                                                    verification: .dispatchFailed), .notPasted)
        XCTAssertEqual(DeliveryPresentation.copyBoxMessage(outcome: .notPasted, verification: .dispatchFailed),
                       "貼り付けを開始できませんでした。ここからコピーできます")
    }

    func testNoEditableTargetShowsCopyBox() {
        XCTAssertEqual(DeliveryPresentation.outcome(plan: .copyBoxOnly, didPaste: false,
                                                    verification: nil), .copyBox)
        XCTAssertNotNil(DeliveryPresentation.copyBoxMessage(outcome: .copyBox, verification: nil))
    }

    func testManualCopyActionExposesOnlyLatestTextOnRequest() {
        let memory = LatestDeliveryMemory()
        XCTAssertEqual(DeliveryPresentation.manualCopyTitle, "直前の文字起こしをコピー")
        var writes: [String] = []
        XCTAssertTrue(writes.isEmpty)
        DeliveryPresentation.copyLatest(from: memory) { writes.append($0) }
        XCTAssertTrue(writes.isEmpty)
        memory.remember("current")
        DeliveryPresentation.copyLatest(from: memory) { writes.append($0) }
        memory.remember("newest")
        DeliveryPresentation.copyLatest(from: memory) { writes.append($0) }
        XCTAssertEqual(writes, ["current", "newest"])
    }

    func testHistoryWarningBlocksRoutineDeliveryMessage() {
        for outcome in [DeliveryOutcome.unverified, .notPasted] {
            XCTAssertNil(DeliveryPresentation.indicatorMessage(outcome: outcome, blockingWarning: true))
        }
    }

    func testWarningThenUnknownDeliveryThenExplicitFailureShowsFailure() {
        var state = DeliveryNoticeState()
        XCTAssertEqual(state.advance(.warning("履歴を保存できませんでした")),
                       .init(text: "履歴を保存できませんでした", isWarning: true))
        XCTAssertNil(state.advance(.delivered(.unverified, polished: false)))
        XCTAssertEqual(state.current?.text, "履歴を保存できませんでした")
        XCTAssertEqual(state.advance(.failed("文字起こしに失敗しました")),
                       .init(text: "文字起こしに失敗しました", isWarning: false))
        XCTAssertEqual(state.current?.text, "文字起こしに失敗しました")
    }

    func testWarningThenUnknownDeliveryThenNothingHeardShowsNewFailure() {
        var state = DeliveryNoticeState()
        _ = state.advance(.warning("履歴を保存できませんでした"))
        XCTAssertNil(state.advance(.delivered(.notPasted, polished: false)))
        XCTAssertEqual(state.advance(.nothingHeard),
                       .init(text: "聞き取れませんでした", isWarning: false))
        XCTAssertEqual(state.current?.text, "聞き取れませんでした")
    }
}
