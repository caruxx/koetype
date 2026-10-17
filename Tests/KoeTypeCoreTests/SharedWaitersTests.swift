import XCTest
@testable import KoeTypeCore

final class SharedWaitersTests: XCTestCase {
    func testOnlyTheFirstCallerAsksAndLaterOnesShareTheResult() {
        var waiters = SharedWaiters<Int>()
        XCTAssertTrue(waiters.add(1, deadline: 100, now: 0))
        XCTAssertFalse(waiters.add(2, deadline: 100, now: 10))
        XCTAssertEqual(waiters.takeAll(), [1, 2])
        // The result went out: the next caller asks again.
        XCTAssertTrue(waiters.add(3, deadline: 200, now: 110))
        XCTAssertEqual(waiters.takeAll(), [3])
    }

    func testCallersStillWaitingAreNeverDroppedHoweverManyThereAre() {
        // A stuck HAL with many callers inside their deadlines: every one of them gets the late result.
        var waiters = SharedWaiters<Int>()
        for caller in 0..<50 { _ = waiters.add(caller, deadline: 1_000, now: UInt64(caller)) }
        XCTAssertEqual(waiters.count, 50)
        XCTAssertEqual(waiters.takeAll(), Array(0..<50))
    }

    func testCallersPastTheirDeadlineAreDroppedWhenSomeoneIsAdded() {
        var waiters = SharedWaiters<Int>()
        XCTAssertTrue(waiters.add(1, deadline: 100, now: 0))
        XCTAssertFalse(waiters.add(2, deadline: 300, now: 50))
        // 1 has already been answered with nil; 2 is still waiting and is kept.
        XCTAssertFalse(waiters.add(3, deadline: 400, now: 150))
        XCTAssertEqual(waiters.count, 2)
        XCTAssertEqual(waiters.takeAll(), [2, 3])
    }

    func testAResultStillOnItsWayIsNotAskedForAgainWhenAllEarlierCallersExpired() {
        // The listing in flight is stuck: everyone before has timed out. A new caller joins it instead
        // of queuing a second listing behind it.
        var waiters = SharedWaiters<Int>()
        XCTAssertTrue(waiters.add(1, deadline: 100, now: 0))
        XCTAssertFalse(waiters.add(2, deadline: 500, now: 200))
        XCTAssertEqual(waiters.count, 1)
    }
}
