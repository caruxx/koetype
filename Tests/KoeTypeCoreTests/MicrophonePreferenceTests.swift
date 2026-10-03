import XCTest
@testable import KoeTypeCore

final class MicrophonePreferenceTests: XCTestCase {
    private let devices = [
        AudioInputDevice(uid: "bt-1", name: "AirPods Pro", isBuiltIn: false),
        AudioInputDevice(uid: "builtin-1", name: "MacBook Proのマイク", isBuiltIn: true),
        AudioInputDevice(uid: "usb-1", name: "Shure MV7", isBuiltIn: false),
    ]

    func testSystemDefaultMeansNoOverride() {
        XCTAssertNil(MicrophonePreference.systemDefault.resolve(among: devices))
    }

    func testBuiltInPicksTheMacsOwnMicrophone() {
        XCTAssertEqual(MicrophonePreference.builtIn.resolve(among: devices)?.uid, "builtin-1")
    }

    func testSpecificDeviceIsUsedWhileConnected() {
        XCTAssertEqual(MicrophonePreference.device(uid: "usb-1").resolve(among: devices)?.name, "Shure MV7")
    }

    func testUnpluggedDeviceFallsBackToTheSystemDefault() {
        XCTAssertNil(MicrophonePreference.device(uid: "gone").resolve(among: devices))
        XCTAssertNil(MicrophonePreference.builtIn.resolve(among: [devices[0]]))
    }

    func testStoredValueRoundTrips() {
        for preference in [MicrophonePreference.systemDefault, .builtIn, .device(uid: "usb-1")] {
            XCTAssertEqual(MicrophonePreference(stored: preference.stored), preference)
        }
        XCTAssertEqual(MicrophonePreference(stored: nil), .systemDefault)   // nothing changes until the user chooses
    }
}
