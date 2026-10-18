import XCTest
@testable import KoeTypeCore

final class ConfigurationChangeCoalescerTests: XCTestCase {
    private final class Engine {}
    private typealias Handling = ConfigurationChangeCoalescer<Engine>.Handling

    func testTheFirstChangeIsHandledAndABurstIsFoldedIntoOneFollowUp() {
        let engine = Engine()
        var coalescer = ConfigurationChangeCoalescer<Engine>()
        XCTAssertEqual(coalescer.arrive(generation: 5, counted: [5], from: engine), Handling(generation: 5, counted: [5]))
        XCTAssertNil(coalescer.arrive(generation: 5, counted: [5], from: engine))
        XCTAssertNil(coalescer.arrive(generation: 5, counted: [5], from: engine))
        let done = coalescer.finish(current: engine)
        XCTAssertEqual(done.followUp, Handling(generation: 5, counted: [5, 5]))
        XCTAssertEqual(done.released, [])
        // The follow-up is handed over still busy: an arrival before it is queued is folded into the
        // next follow-up, keeping its own generation.
        XCTAssertNil(coalescer.arrive(generation: 6, counted: [6], from: engine))
        XCTAssertEqual(coalescer.finish(current: engine).followUp, Handling(generation: 6, counted: [6]))
        XCTAssertEqual(coalescer.finish(current: engine).followUp, nil)
        // Idle again: the next change is handled at once.
        XCTAssertEqual(coalescer.arrive(generation: 6, counted: [6], from: engine), Handling(generation: 6, counted: [6]))
    }

    func testAChangeForANewerRecordingKeepsItsOwnCountWhileTheOlderHandlingRuns() {
        // Recording 5's handling runs; recording 6 starts and its engine posts a change. That arrival is
        // counted for 6 at once and the count travels with the follow-up until it is over.
        let engine = Engine()
        var coalescer = ConfigurationChangeCoalescer<Engine>()
        _ = coalescer.arrive(generation: 5, counted: [5], from: engine)
        XCTAssertNil(coalescer.arrive(generation: 6, counted: [6], from: engine))
        XCTAssertEqual(coalescer.finish(current: engine).followUp, Handling(generation: 6, counted: [6]))
    }

    func testTheFollowUpIsForTheEngineInUseWhenItChangedMeanwhile() {
        // Engine A's handling runs; A is replaced by B, whose change is folded in. The follow-up is for B.
        let a = Engine(), b = Engine()
        var coalescer = ConfigurationChangeCoalescer<Engine>()
        _ = coalescer.arrive(generation: 5, counted: [5], from: a)
        XCTAssertNil(coalescer.arrive(generation: 5, counted: [5], from: b))
        let done = coalescer.finish(current: b)
        XCTAssertEqual(done.followUp, Handling(generation: 5, counted: [5]))
        XCTAssertEqual(done.released, [])
    }

    func testChangesOnlyOfAReplacedEngineAreReleasedWithoutAFollowUp() {
        let a = Engine(), b = Engine()
        var coalescer = ConfigurationChangeCoalescer<Engine>()
        _ = coalescer.arrive(generation: 5, counted: [5], from: a)
        XCTAssertNil(coalescer.arrive(generation: 5, counted: [5], from: a))
        let done = coalescer.finish(current: b)
        XCTAssertNil(done.followUp)
        XCTAssertEqual(done.released, [5])
        let none = coalescer.finish(current: nil)
        XCTAssertNil(none.followUp)
        XCTAssertEqual(none.released, [])
    }

    func testWithNoEngineInUseFoldedCountsAreReleased() {
        let a = Engine()
        var coalescer = ConfigurationChangeCoalescer<Engine>()
        _ = coalescer.arrive(generation: 5, counted: [5], from: a)
        _ = coalescer.arrive(generation: 6, counted: [6], from: a)
        XCTAssertEqual(coalescer.finish(current: nil).released, [6])
    }
}
