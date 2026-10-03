import XCTest
@testable import KoeTypeCore

final class SmokeTests: XCTestCase {
    func testVersionIsSet() {
        XCTAssertEqual(KoeTypeCore.version, "0.1.0")
    }
}
