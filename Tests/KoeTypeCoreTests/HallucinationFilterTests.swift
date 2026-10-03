import XCTest
@testable import KoeTypeCore

final class HallucinationFilterTests: XCTestCase {
    func testKnownPhantomPhrasesBecomeEmpty() {
        XCTAssertEqual(HallucinationFilter.clean("ご視聴ありがとうございました"), "")
        XCTAssertEqual(HallucinationFilter.clean(" ご視聴ありがとうございました。 "), "")
        XCTAssertEqual(HallucinationFilter.clean("チャンネル登録お願いします!"), "")
        XCTAssertEqual(HallucinationFilter.clean("(音楽)"), "")
        XCTAssertEqual(HallucinationFilter.clean("   \n"), "")
    }

    func testRealSpeechIsKeptAndTrimmed() {
        XCTAssertEqual(HallucinationFilter.clean(" 明日の会議は10時からです "), "明日の会議は10時からです")
        // A phantom phrase inside real speech must survive: the user may really say it.
        XCTAssertEqual(HallucinationFilter.clean("動画の最後にご視聴ありがとうございましたと入れてください"),
                       "動画の最後にご視聴ありがとうございましたと入れてください")
    }

    func testSegmentsThatBeginInThePaddedSilenceAreDropped() {
        let segments = [
            SpeechSegment(text: "以上で本日の連絡を終わります。", start: 64.0),
            SpeechSegment(text: "ご視聴ありがとうございました", start: 70.1),   // measured: begins as speech ends
        ]
        XCTAssertEqual(HallucinationFilter.join(segments, speechEnd: 70.4), "以上で本日の連絡を終わります。")
    }

    func testSegmentsWithinTheSpeechAreKeptEvenIfTheyLookLikePhantoms() {
        // The user really said it: it starts well before the audio ends.
        let segments = [
            SpeechSegment(text: "今日はここまでです。", start: 0),
            SpeechSegment(text: "ご視聴ありがとうございました。", start: 2.1),
        ]
        XCTAssertEqual(HallucinationFilter.join(segments, speechEnd: 4.5), "今日はここまでです。ご視聴ありがとうございました。")
    }

    func testFirstSegmentIsNeverDroppedByPosition() {
        XCTAssertEqual(HallucinationFilter.join([SpeechSegment(text: "はい。", start: 0.4)], speechEnd: 0.4), "はい。")
    }

    func testPhantomPhraseSqueezedIntoTheLastMomentIsDropped() {
        // Measured with real audio: 6.55 s of speech, phantom segment placed at 6.26-7.26.
        let segments = [
            SpeechSegment(text: "先日ご依頼いただいた見積書を本日お送りいたします。", start: 1.82),
            SpeechSegment(text: "ありがとうございました", start: 6.26),
        ]
        XCTAssertEqual(HallucinationFilter.join(segments, speechEnd: 6.55), "先日ご依頼いただいた見積書を本日お送りいたします。")
    }

    func testShortRealWordAtTheEndIsKept() {
        let segments = [
            SpeechSegment(text: "それでお願いします。", start: 0),
            SpeechSegment(text: "はい。", start: 2.2),
        ]
        XCTAssertEqual(HallucinationFilter.join(segments, speechEnd: 2.6), "それでお願いします。はい。")
    }
}
