import XCTest
@testable import KoeTypeCore

final class IndicatorPolicyTests: XCTestCase {
    func testRecordingWinsOverEverything() {
        XCTAssertEqual(IndicatorPolicy.display(recording: .handsFree, message: "聞き取れませんでした", pending: 2, stage: .polishing),
                       .recording(handsFree: true))
        XCTAssertEqual(IndicatorPolicy.display(recording: .holding, message: nil, pending: 0, stage: .transcribing),
                       .recording(handsFree: false))
    }

    func testMessageStaysVisibleWhileOtherJobsAreStillRunning() {
        XCTAssertEqual(IndicatorPolicy.display(recording: .none, message: "聞き取れませんでした", pending: 1, stage: .transcribing),
                       .message("聞き取れませんでした"))
    }

    func testPendingWorkShowsItsStage() {
        XCTAssertEqual(IndicatorPolicy.display(recording: .none, message: nil, pending: 1, stage: .polishing),
                       .working(.polishing))
    }

    func testNothingToShowHides() {
        XCTAssertEqual(IndicatorPolicy.display(recording: .none, message: nil, pending: 0, stage: .transcribing), .hidden)
    }
}
