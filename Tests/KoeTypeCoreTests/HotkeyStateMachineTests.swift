import XCTest
@testable import KoeTypeCore

final class HotkeyStateMachineTests: XCTestCase {
    typealias Action = HotkeyStateMachine.Action

    func testHoldAndReleaseProcesses() {
        var machine = HotkeyStateMachine()
        XCTAssertEqual(machine.handle(.triggerDown, at: 0), [.startRecording])
        XCTAssertTrue(machine.isRecording)
        XCTAssertEqual(machine.handle(.triggerUp, at: 1.0), [.stopAndProcess])
        XCTAssertFalse(machine.isRecording)
    }

    func testShortTapCancels() {
        var machine = HotkeyStateMachine()
        _ = machine.handle(.triggerDown, at: 0)
        XCTAssertEqual(machine.handle(.triggerUp, at: 0.1), [.cancelRecording])
        XCTAssertFalse(machine.isRecording)
    }

    func testDoubleTapEntersHandsFreeAndNextPressStops() {
        var machine = HotkeyStateMachine()
        _ = machine.handle(.triggerDown, at: 0)
        _ = machine.handle(.triggerUp, at: 0.1)
        XCTAssertEqual(machine.handle(.triggerDown, at: 0.3), [.startRecording, .enterHandsFree])
        XCTAssertTrue(machine.isHandsFree)
        XCTAssertEqual(machine.handle(.triggerUp, at: 0.4), [])
        XCTAssertEqual(machine.handle(.otherKeyDown, at: 2), [])
        XCTAssertTrue(machine.isRecording)
        XCTAssertEqual(machine.handle(.triggerDown, at: 30), [.stopAndProcess])
        XCTAssertEqual(machine.handle(.triggerUp, at: 30.1), [])
        XCTAssertFalse(machine.isRecording)
        XCTAssertEqual(machine.handle(.triggerDown, at: 40), [.startRecording])
    }

    func testSlowSecondTapIsAnOrdinaryHold() {
        var machine = HotkeyStateMachine()
        _ = machine.handle(.triggerDown, at: 0)
        _ = machine.handle(.triggerUp, at: 0.1)
        XCTAssertEqual(machine.handle(.triggerDown, at: 0.6), [.startRecording])
        XCTAssertFalse(machine.isHandsFree)
        XCTAssertEqual(machine.handle(.triggerUp, at: 2), [.stopAndProcess])
    }

    func testOtherKeyWhileHoldingCancelsUntilRelease() {
        var machine = HotkeyStateMachine()
        _ = machine.handle(.triggerDown, at: 0)
        XCTAssertEqual(machine.handle(.otherKeyDown, at: 0.5), [.cancelRecording])
        XCTAssertEqual(machine.handle(.otherKeyDown, at: 0.6), [])
        XCTAssertEqual(machine.handle(.triggerUp, at: 1), [])
        XCTAssertEqual(machine.handle(.triggerDown, at: 2), [.startRecording])
    }

    func testEscapeCancelsHoldAndHandsFree() {
        var hold = HotkeyStateMachine()
        _ = hold.handle(.triggerDown, at: 0)
        XCTAssertEqual(hold.handle(.escape, at: 1), [.cancelRecording])
        XCTAssertEqual(hold.handle(.triggerUp, at: 1.2), [])

        var free = HotkeyStateMachine()
        _ = free.handle(.triggerDown, at: 0)
        _ = free.handle(.triggerUp, at: 0.1)
        _ = free.handle(.triggerDown, at: 0.2)
        _ = free.handle(.triggerUp, at: 0.3)
        XCTAssertEqual(free.handle(.escape, at: 5), [.cancelRecording])
        XCTAssertFalse(free.isRecording)
    }

    func testIdleIgnoresNoise() {
        var machine = HotkeyStateMachine()
        XCTAssertEqual(machine.handle(.triggerUp, at: 0), [])
        XCTAssertEqual(machine.handle(.otherKeyDown, at: 0), [])
        XCTAssertEqual(machine.handle(.escape, at: 0), [])
    }

    func testResetReturnsToIdle() {
        var machine = HotkeyStateMachine()
        _ = machine.handle(.triggerDown, at: 0)
        machine.reset()
        XCTAssertFalse(machine.isRecording)
        XCTAssertEqual(machine.handle(.triggerDown, at: 1), [.startRecording])
    }
}
