import XCTest
@testable import KoeTypeCore

final class HotkeyEventClassifierTests: XCTestCase {
    private let rightCommand = HotkeyEventClassifier.Trigger(deviceMask: 0x10)
    private let leftCommand: UInt64 = 0x8
    private let genericCommand: UInt64 = 0x100000
    private let leftShift: UInt64 = 0x2

    func testTriggerDownAndUpFollowTheDeviceBit() {
        var classifier = HotkeyEventClassifier(trigger: rightCommand)
        XCTAssertEqual(classifier.classify(.flagsChanged, keyCode: 54, flags: 0x10 | genericCommand, fromSelf: false), .triggerDown)
        XCTAssertNil(classifier.classify(.flagsChanged, keyCode: 54, flags: 0x10 | genericCommand, fromSelf: false))
        XCTAssertEqual(classifier.classify(.flagsChanged, keyCode: 54, flags: 0, fromSelf: false), .triggerUp)
    }

    func testReleaseIsSeenEvenWhileTheLeftCommandIsStillHeld() {
        var classifier = HotkeyEventClassifier(trigger: rightCommand)
        _ = classifier.classify(.flagsChanged, keyCode: 55, flags: leftCommand | genericCommand, fromSelf: false)
        XCTAssertEqual(classifier.classify(.flagsChanged, keyCode: 54, flags: leftCommand | 0x10 | genericCommand, fromSelf: false), .triggerDown)
        // Generic command flag is still set by the left key; only the device bit tells the truth.
        XCTAssertEqual(classifier.classify(.flagsChanged, keyCode: 54, flags: leftCommand | genericCommand, fromSelf: false), .triggerUp)
    }

    func testLeftCommandAloneIsAnotherKeyNotTheTrigger() {
        var classifier = HotkeyEventClassifier(trigger: rightCommand)
        XCTAssertEqual(classifier.classify(.flagsChanged, keyCode: 55, flags: leftCommand | genericCommand, fromSelf: false),
                       .otherKeyDown)
    }

    func testPressingAnotherModifierWhileHoldingCountsAsOtherKey() {
        var classifier = HotkeyEventClassifier(trigger: rightCommand)
        _ = classifier.classify(.flagsChanged, keyCode: 54, flags: 0x10, fromSelf: false)
        XCTAssertEqual(classifier.classify(.flagsChanged, keyCode: 56, flags: 0x10 | leftShift, fromSelf: false), .otherKeyDown)
    }

    func testReleasingAnotherModifierIsIgnored() {
        var classifier = HotkeyEventClassifier(trigger: rightCommand)
        _ = classifier.classify(.flagsChanged, keyCode: 56, flags: leftShift, fromSelf: false)
        _ = classifier.classify(.flagsChanged, keyCode: 54, flags: 0x10 | leftShift, fromSelf: false)
        XCTAssertNil(classifier.classify(.flagsChanged, keyCode: 56, flags: 0x10, fromSelf: false))
    }

    func testKeysAndPointerEvents() {
        var classifier = HotkeyEventClassifier(trigger: rightCommand)
        XCTAssertEqual(classifier.classify(.keyDown, keyCode: 53, flags: 0, fromSelf: false), .escape)
        XCTAssertEqual(classifier.classify(.keyDown, keyCode: 8, flags: 0x10, fromSelf: false), .otherKeyDown)
        XCTAssertEqual(classifier.classify(.pointer, keyCode: 0, flags: 0x10, fromSelf: false), .otherKeyDown)
    }

    func testOurOwnSyntheticPasteIsInvisible() {
        var classifier = HotkeyEventClassifier(trigger: rightCommand)
        _ = classifier.classify(.flagsChanged, keyCode: 54, flags: 0x10, fromSelf: false)
        XCTAssertNil(classifier.classify(.keyDown, keyCode: 9, flags: genericCommand, fromSelf: true))
        XCTAssertNil(classifier.classify(.flagsChanged, keyCode: 54, flags: 0, fromSelf: true))
        XCTAssertEqual(classifier.classify(.flagsChanged, keyCode: 54, flags: 0, fromSelf: false), .triggerUp)
    }

    func testResyncReportsAReleaseThatWasMissed() {
        var classifier = HotkeyEventClassifier(trigger: rightCommand)
        _ = classifier.classify(.flagsChanged, keyCode: 54, flags: 0x10, fromSelf: false)
        XCTAssertNil(classifier.resync(flags: 0x10))
        XCTAssertEqual(classifier.resync(flags: 0), .triggerUp)
        XCTAssertNil(classifier.resync(flags: 0))
    }

    func testFnTriggerUsesTheSecondaryFnFlag() {
        var classifier = HotkeyEventClassifier(trigger: .init(deviceMask: 0x800000))
        XCTAssertEqual(classifier.classify(.flagsChanged, keyCode: 63, flags: 0x800000, fromSelf: false), .triggerDown)
        XCTAssertEqual(classifier.classify(.flagsChanged, keyCode: 63, flags: 0, fromSelf: false), .triggerUp)
    }
}
