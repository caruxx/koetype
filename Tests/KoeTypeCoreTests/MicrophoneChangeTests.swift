import XCTest
@testable import KoeTypeCore

final class MicrophoneChangeTests: XCTestCase {
    func testProfileSwitchOfTheSameHeadsetKeepsRecording() {
        XCTAssertEqual(MicrophoneChange.classify(startedOn: "bt-1:input", now: "bt-1:input"), .sameMicrophone)
    }

    func testAnotherMicrophoneTakingOverIsASwitch() {
        XCTAssertEqual(MicrophoneChange.classify(startedOn: "bt-1:input", now: "BuiltInMicrophoneDevice"), .switched)
    }

    func testNoInputLeftIsASwitch() {
        XCTAssertEqual(MicrophoneChange.classify(startedOn: "bt-1:input", now: nil), .switched)
    }

    func testUnknownStartingMicrophoneIsNeverReportedAsASwitch() {
        XCTAssertEqual(MicrophoneChange.classify(startedOn: nil, now: "bt-1:input"), .sameMicrophone)
        XCTAssertEqual(MicrophoneChange.classify(startedOn: nil, now: nil), .sameMicrophone)
    }
}
