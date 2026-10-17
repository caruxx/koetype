import XCTest
@testable import KoeTypeCore

final class DeadlineTests: XCTestCase {
    func testAResultBeforeTheDeadlineIsReturned() async {
        let value = await Deadline.first(within: 1) { done in done(42) }
        XCTAssertEqual(value, 42)
    }

    func testADeadlineWithNoResultReturnsNilInTime() async {
        let began = Date()
        let value: Int? = await Deadline.first(within: 0.1) { _ in }   // never calls back, like a stuck HAL
        XCTAssertNil(value)
        XCTAssertLessThan(Date().timeIntervalSince(began), 1)
    }

    func testAResultArrivingAfterTheDeadlineIsDropped() async {
        final class Late: @unchecked Sendable { var done: (@Sendable (Int) -> Void)? }
        let late = Late()
        let value = await Deadline.first(within: 0.05) { done in late.done = done }
        XCTAssertNil(value)
        late.done?(7)   // the continuation was already resumed by the deadline: this must be ignored
        XCTAssertNil(value)
    }

    func testAResultDeliveredFromAnotherQueueBeforeTheDeadlineWins() async {
        let value = await Deadline.first(within: 1) { done in
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.02) { done("ok") }
        }
        XCTAssertEqual(value, "ok")
    }

    func testOnlyTheFirstClaimIsAdmitted() {
        let claim = FirstClaim()
        var admitted = 0
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: 50) { _ in
            if claim.take() { lock.withLock { admitted += 1 } }
        }
        XCTAssertEqual(admitted, 1)
        XCTAssertFalse(claim.take())
    }
}
