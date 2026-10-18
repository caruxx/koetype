import XCTest
@testable import KoeTypeCore

final class InputFormatAlignmentTests: XCTestCase {
    func testInputFormatIsAlignedOnlyWhenTheHardwareDiffers() {
        // The Shokz in its call profile behind the 48 kHz format left by the default device.
        XCTAssertTrue(InputFormatAlignment.needed(pointedAtDevice: true, hardwareRate: 16_000, hardwareChannels: 1, outputRate: 48_000, outputChannels: 1))
        XCTAssertTrue(InputFormatAlignment.needed(pointedAtDevice: true, hardwareRate: 48_000, hardwareChannels: 2, outputRate: 48_000, outputChannels: 1))
        XCTAssertFalse(InputFormatAlignment.needed(pointedAtDevice: true, hardwareRate: 48_000, hardwareChannels: 1, outputRate: 48_000, outputChannels: 1))
        // No usable hardware format: nothing to align to, the start reports no input device.
        XCTAssertFalse(InputFormatAlignment.needed(pointedAtDevice: true, hardwareRate: 0, hardwareChannels: 0, outputRate: 48_000, outputChannels: 1))
    }

    func testAnEngineFollowingTheSystemDefaultIsNeverAligned() {
        // Even mid-change, when the formats briefly disagree, the default path is left as it was.
        XCTAssertFalse(InputFormatAlignment.needed(pointedAtDevice: false, hardwareRate: 16_000, hardwareChannels: 1, outputRate: 48_000, outputChannels: 1))
        XCTAssertFalse(InputFormatAlignment.needed(pointedAtDevice: false, hardwareRate: 48_000, hardwareChannels: 2, outputRate: 48_000, outputChannels: 1))
    }
}
