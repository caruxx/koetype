import XCTest
@testable import KoeTypeCore

final class DictionaryCorrectionTests: XCTestCase {
    func testExplicitAliasesInMixedJapaneseAndEnglish() {
        let entries = [DictionaryEntry(term: "KoeType", variants: ["コエタイプ"]),
                       DictionaryEntry(term: "Product Hunt", variants: ["ProductHunt"])]
        XCTAssertEqual(DictionaryCorrection.apply(to: "コエタイプをProductHuntで紹介します。", entries: entries),
                       "KoeTypeをProduct Huntで紹介します。")
    }

    func testDoesNotReplacePartsOfWordsOrCodeIdentifiers() {
        let entries = [DictionaryEntry(term: "Ion", variants: ["イオン"]),
                       DictionaryEntry(term: "correct", variants: ["flow"])]
        let text = "ライオン airflow flow_id flow-name flow/path flow.example"
        XCTAssertEqual(DictionaryCorrection.apply(to: text, entries: entries), text)
    }

    func testConflictingAliasesAndCanonicalTermsStayUnchanged() {
        let entries = [DictionaryEntry(term: "Alpha", variants: ["same", "Beta"]),
                       DictionaryEntry(term: "Beta", variants: ["same"])]
        XCTAssertEqual(DictionaryCorrection.apply(to: "same Beta Alpha", entries: entries), "same Beta Alpha")
    }

    func testLongestAliasWinsAndOutputIsNotScannedAgain() {
        let entries = [DictionaryEntry(term: "Long", variants: ["old name"]),
                       DictionaryEntry(term: "Short", variants: ["old"]),
                       DictionaryEntry(term: "middle", variants: ["start"]),
                       DictionaryEntry(term: "end", variants: ["middle"])]
        XCTAssertEqual(DictionaryCorrection.apply(to: "old name start middle", entries: entries), "Long middle middle")
    }

    func testWhitespaceEmptyAliasesDuplicatesAndExactCase() {
        let entries = [DictionaryEntry(term: " Output ", variants: ["", " ", " alias ", "alias"])]
        XCTAssertEqual(DictionaryCorrection.apply(to: "alias ALIAS", entries: entries), "Output ALIAS")
        XCTAssertEqual(DictionaryCorrection.apply(to: "", entries: entries), "")
    }

    func testNumbersNegationAndUnregisteredWordsAreUntouched() {
        let entries = [DictionaryEntry(term: "KoeType", variants: ["コエタイプ"])]
        XCTAssertEqual(DictionaryCorrection.apply(to: "API-2は使わない。価格は1,200円。", entries: entries),
                       "API-2は使わない。価格は1,200円。")
    }
    func testJapaneseCompoundNamesAreNotPartiallyCorrected() {
        let entries = [DictionaryEntry(term: "別の都市", variants: ["東京"]),
                       DictionaryEntry(term: "KoeType", variants: ["コエタイプ"])]
        let text = "東京大学 東京都 コエタイプス"
        XCTAssertEqual(DictionaryCorrection.apply(to: text, entries: entries), text)
        XCTAssertEqual(DictionaryCorrection.apply(to: "東京に行く。コエタイプを使う。", entries: entries),
                       "別の都市に行く。KoeTypeを使う。")
    }

    func testSentencePunctuationIsNotAnIdentifierContinuation() {
        let entries = [DictionaryEntry(term: "Flow", variants: ["flow"])]
        XCTAssertEqual(DictionaryCorrection.apply(to: "flow. flow! flow-name", entries: entries),
                       "Flow. Flow! flow-name")
    }

    func testURLsAddressesHandlesAndCodeSpansRemainLiteral() {
        let entries = [DictionaryEntry(term: "Flow", variants: ["flow"])]
        let text = #"https://flow http://flow/path flow://host flow@example.com @flow #flow `flow` flow::method flow\path flow() --flow"#
        XCTAssertEqual(DictionaryCorrection.apply(to: text, entries: entries), text)
        XCTAssertEqual(DictionaryCorrection.apply(to: "flow", entries: entries), "Flow")
    }

}
