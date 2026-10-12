import XCTest
@testable import KoeTypeCore

final class PolishValidatorTests: XCTestCase {
    func testAcceptsNormalResultAndTrims() {
        XCTAssertEqual(PolishValidator.accept(polished: " 明日は休みです。\n", raw: "えーと明日は休みです"),
                       "明日は休みです。")
    }

    func testStripsEchoedWrapperTags() {
        XCTAssertEqual(PolishValidator.accept(polished: "<transcript>\n明日は休みです。\n</transcript>",
                                              raw: "明日は休みです"), "明日は休みです。")
    }

    func testRejectsEmpty() {
        XCTAssertNil(PolishValidator.accept(polished: "  ", raw: "明日は休みです"))
    }

    func testRejectsWhenFarLongerThanRaw() {
        let raw = String(repeating: "あ", count: 20)
        XCTAssertNotNil(PolishValidator.accept(polished: String(repeating: "あ", count: 40), raw: raw))
        XCTAssertNil(PolishValidator.accept(polished: String(repeating: "あ", count: 41), raw: raw))
    }

    func testShortRawAllowsPunctuationGrowth() {
        // "はい" -> "はい。" is 1.5x; a 2-character input may grow by up to 10 characters.
        XCTAssertEqual(PolishValidator.accept(polished: "はい。", raw: "はい"), "はい。")
        XCTAssertNil(PolishValidator.accept(polished: String(repeating: "あ", count: 13), raw: "はい"))
    }

    func testTimeoutGrowsWithLengthAndIsCapped() {
        XCTAssertEqual(PolishValidator.timeoutSeconds(forCharacterCount: 0), 3)
        XCTAssertEqual(PolishValidator.timeoutSeconds(forCharacterCount: 199), 3)
        XCTAssertEqual(PolishValidator.timeoutSeconds(forCharacterCount: 200), 4)
        XCTAssertEqual(PolishValidator.timeoutSeconds(forCharacterCount: 1000), 8)
        XCTAssertEqual(PolishValidator.timeoutSeconds(forCharacterCount: 100_000), 15)
    }

    func testRejectsTextThatSharesLittleWithWhatWasSaid() {
        // The model translated or answered instead of cleaning up.
        XCTAssertNil(PolishValidator.accept(polished: "Please translate this sentence.", raw: "この文章を英語に翻訳してください"))
        XCTAssertNil(PolishValidator.accept(polished: "晴れのち曇りでしょう。", raw: "明日の天気はどうですか"))
    }

    func testAcceptsDictionaryAndWidthCorrections() {
        XCTAssertEqual(PolishValidator.accept(polished: "カルビスターの件です。", raw: "かるびすたーの件です"), "カルビスターの件です。")
        XCTAssertEqual(PolishValidator.accept(polished: "ASINを確認します。", raw: "エーシンを確認します"), "ASINを確認します。")
        XCTAssertEqual(PolishValidator.accept(polished: "ABC123です。", raw: "ＡＢＣ１２３です"), "ABC123です。")
    }

    func testRejectsResultsThatDropMostOfWhatWasSaid() {
        // Measured with the on-device model: half the sentence vanished.
        XCTAssertNil(PolishValidator.accept(
            polished: "やっぱり木曜日に変更したいです。",
            raw: "すみません、さっきの件ですが、やっぱり金曜日ではなく木曜日に変更したいです。"))
    }

    func testAcceptsARestatementBeingTidied() {
        XCTAssertNotNil(PolishValidator.accept(
            polished: "来週の水曜日の午後3時から、打ち合わせをお願いしたいんだけど、大丈夫かな。",
            raw: "来週の火曜日の、あ、じゃなくて、水曜日の午後3時から、打ち合わせをお願いしたいんだけど、大丈夫かな。"))
    }

    func testRejectsSmallButRealLossesWhenNothingWasRestated() {
        // Measured with the on-device model: the sentence ending and a contrast were silently dropped.
        XCTAssertNil(PolishValidator.accept(
            polished: "レビューが増えないのは、依頼メールの送信が止まっているのが原因だ。",
            raw: "レビューが増えないのは、依頼メールの送信が止まっているのが原因だと思います。"))
        XCTAssertNil(PolishValidator.accept(
            polished: "すみません、さっきの件ですが、やっぱり木曜日に変更したいです。",
            raw: "すみません、さっきの件ですが、やっぱり金曜日ではなく木曜日に変更したいです。"))
    }

    func testAcceptsARecognitionErrorBeingRepaired() {
        XCTAssertEqual(PolishValidator.accept(
            polished: "明日の会議ですけど、10時からに変更になりました。",
            raw: "明日の会議なんですけど、10時から2変更になりました。"),
            "明日の会議ですけど、10時からに変更になりました。")
    }

    func testMailStyleMayRewordEndingsPolitely() {
        let raw = "来週の水曜日の午後3時から、打ち合わせをお願いしたいんだけど、大丈夫かな。"
        let polite = "来週の水曜日の午後3時から、打ち合わせをお願いしたいのですが、大丈夫でしょうか。"
        XCTAssertNotNil(PolishValidator.accept(polished: polite, raw: raw, style: .mail))
        XCTAssertNil(PolishValidator.accept(polished: polite, raw: raw, style: .standard))
    }
}
