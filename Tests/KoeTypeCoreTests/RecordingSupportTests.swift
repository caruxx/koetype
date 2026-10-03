import XCTest
@testable import KoeTypeCore

final class AudioMixerTests: XCTestCase {
    func testSumsTwoStreamsAndKeepsTheLongerLength() {
        XCTAssertEqual(AudioMixer.mix([0.1, 0.2, 0.3], [0.1, 0.1]), [0.2, 0.3, 0.3], accuracy: 0.0001)
    }

    func testClipsInsteadOfOverflowing() {
        XCTAssertEqual(AudioMixer.mix([0.8, -0.9], [0.7, -0.6]), [1.0, -1.0], accuracy: 0.0001)
    }

    func testOneEmptyStreamReturnsTheOther() {
        XCTAssertEqual(AudioMixer.mix([], [0.5]), [0.5])
    }
}

final class AudioChunkerTests: XCTestCase {
    func testShortAudioIsOneChunk() {
        let samples = [Float](repeating: 0.5, count: 1_000)
        XCTAssertEqual(AudioChunker.ranges(for: samples, sampleRate: 100, targetSeconds: 30, searchSeconds: 5), [0..<1_000])
    }

    func testCutsAtTheQuietestMomentNearEachBoundary() {
        // 100 Hz for easy numbers: 70 s of sound with a silent gap at 27.0-27.5 s.
        var samples = [Float](repeating: 0.5, count: 7_000)
        for index in 2_700..<2_750 { samples[index] = 0 }
        let ranges = AudioChunker.ranges(for: samples, sampleRate: 100, targetSeconds: 30, searchSeconds: 5)
        XCTAssertEqual(ranges.first, 0..<2_725)   // middle of the gap, not the 30 s mark
        XCTAssertEqual(ranges.last?.upperBound, 7_000)
        // Chunks are contiguous and cover everything exactly once.
        XCTAssertEqual(ranges.map(\.count).reduce(0, +), 7_000)
        for (previous, next) in zip(ranges, ranges.dropFirst()) { XCTAssertEqual(previous.upperBound, next.lowerBound) }
        XCTAssertTrue(ranges.allSatisfy { $0.count <= 3_000 })
    }
}

final class TranscriptFormatterTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_790_000_000)   // 2026-09-21 23:13:20 JST
    private let tokyo = TimeZone(identifier: "Asia/Tokyo")!

    func testFormatsTimestampedLines() {
        let text = TranscriptFormatter.markdown(
            title: "記録", startedAt: date, durationSeconds: 3_725,
            segments: [SpeechSegment(text: " それでは始めます。", start: 0.4),
                       SpeechSegment(text: "次の議題です。", start: 75.2),
                       SpeechSegment(text: "以上です。", start: 3_700)],
            timeZone: tokyo)
        XCTAssertEqual(text, """
        # 記録 2026-09-21 23:13

        - 長さ: 1:02:05

        [0:00:00] それでは始めます。
        [0:01:15] 次の議題です。
        [1:01:40] 以上です。

        """)
    }

    func testDropsEmptyAndPhantomSegments() {
        let text = TranscriptFormatter.markdown(
            title: "記録", startedAt: date, durationSeconds: 20,
            segments: [SpeechSegment(text: "  ", start: 0), SpeechSegment(text: "ご視聴ありがとうございました", start: 3),
                       SpeechSegment(text: "本題に入ります。", start: 8)],
            timeZone: tokyo)
        XCTAssertFalse(text.contains("ご視聴"))
        XCTAssertTrue(text.contains("[0:00:08] 本題に入ります。"))
    }

    func testNothingRecognisedSaysSo() {
        let text = TranscriptFormatter.markdown(title: "記録", startedAt: date, durationSeconds: 5, segments: [], timeZone: tokyo)
        XCTAssertTrue(text.contains("（聞き取れた音声がありませんでした）"))
    }

    func testFileNameIsSortableAndSafe() {
        XCTAssertEqual(TranscriptFormatter.fileName(title: "会議/打合せ: A社", startedAt: date, timeZone: tokyo),
                       "2026-09-21_2313_会議-打合せ- A社.md")
    }
}

private func XCTAssertEqual(_ lhs: [Float], _ rhs: [Float], accuracy: Float, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(lhs.count, rhs.count, file: file, line: line)
    for (a, b) in zip(lhs, rhs) { XCTAssertEqual(a, b, accuracy: accuracy, file: file, line: line) }
}
