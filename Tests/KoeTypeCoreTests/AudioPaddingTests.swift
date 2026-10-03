import XCTest
@testable import KoeTypeCore

final class AudioPaddingTests: XCTestCase {
    func testAppendsTrailingSilenceSoShortUtterancesSurviveWindowClipping() {
        let samples = [Float](repeating: 0.5, count: 8_000)   // 0.5 s at 16 kHz
        let padded = AudioPadding.withTrailingSilence(samples, sampleRate: 16_000, seconds: 1.2)
        XCTAssertEqual(padded.count, 8_000 + 19_200)
        XCTAssertEqual(Array(padded.prefix(8_000)), samples)
        XCTAssertTrue(padded.suffix(19_200).allSatisfy { $0 == 0 })
    }

    func testEmptyInputStaysEmpty() {
        XCTAssertTrue(AudioPadding.withTrailingSilence([], sampleRate: 16_000, seconds: 1.2).isEmpty)
    }
}
