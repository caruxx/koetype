import XCTest
@testable import KoeTypeCore

final class RecordingLimitTests: XCTestCase {
    private let began = Date(timeIntervalSince1970: 1_790_000_000)

    func testTheLimitIsReachedAfterMaxSecondsRegardlessOfSamples() {
        XCTAssertTrue(RecordingLimit.reached(startedAt: began, now: began.addingTimeInterval(7_200), maxSeconds: 7_200))
        XCTAssertTrue(RecordingLimit.reached(startedAt: began, now: began.addingTimeInterval(7_201), maxSeconds: 7_200))
    }

    func testTheLimitIsNotReachedBefore() {
        XCTAssertFalse(RecordingLimit.reached(startedAt: began, now: began.addingTimeInterval(7_199), maxSeconds: 7_200))
        XCTAssertFalse(RecordingLimit.reached(startedAt: began, now: began, maxSeconds: 7_200))
    }
}
