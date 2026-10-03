import XCTest
@testable import KoeTypeCore

final class PolishStyleTests: XCTestCase {
    func testBuiltInRulesCoverCommonApps() {
        let rules = AppStyleRules(overrides: [:])
        XCTAssertEqual(rules.style(forBundleID: "com.tinyspeck.slackmacgap"), .chat)
        XCTAssertEqual(rules.style(forBundleID: "jp.naver.line.mac"), .chat)
        XCTAssertEqual(rules.style(forBundleID: "com.apple.mail"), .mail)
        XCTAssertEqual(rules.style(forBundleID: "com.apple.Terminal"), .minimal)
        XCTAssertEqual(rules.style(forBundleID: "com.microsoft.VSCode"), .minimal)
    }

    func testUnknownOrMissingAppIsStandard() {
        let rules = AppStyleRules(overrides: [:])
        XCTAssertEqual(rules.style(forBundleID: "com.example.unknown"), .standard)
        XCTAssertEqual(rules.style(forBundleID: nil), .standard)
    }

    func testUserChoiceWinsOverTheBuiltInRule() {
        let rules = AppStyleRules(overrides: ["com.apple.Terminal": .standard, "com.google.Chrome": .chat])
        XCTAssertEqual(rules.style(forBundleID: "com.apple.Terminal"), .standard)
        XCTAssertEqual(rules.style(forBundleID: "com.google.Chrome"), .chat)
        XCTAssertEqual(rules.all["com.apple.mail"], .mail)
        XCTAssertEqual(rules.all["com.google.Chrome"], .chat)
    }

    func testOverridesRoundTripThroughStoredStrings() {
        let stored = AppStyleRules.encode(["com.google.Chrome": .chat])
        XCTAssertEqual(stored, ["com.google.Chrome": "chat"])
        XCTAssertEqual(AppStyleRules.decode(["com.google.Chrome": "chat", "x": "nonsense"]), ["com.google.Chrome": .chat])
    }

    func testStyleChangesTheInstructions() {
        let standard = PolishPrompt.system(dictionary: [], style: .standard)
        let chat = PolishPrompt.system(dictionary: [], style: .chat)
        let mail = PolishPrompt.system(dictionary: [], style: .mail)
        XCTAssertFalse(standard.contains("宛先"))
        XCTAssertTrue(chat.contains("チャット"))
        XCTAssertTrue(mail.contains("メール"))
        XCTAssertTrue(mail.contains("です・ます"))
    }

    func testChatStyleDropsOnlyTheFinalFullStop() {
        XCTAssertEqual(PolishStyle.chat.finalized("了解です。明日対応します。"), "了解です。明日対応します")
        XCTAssertEqual(PolishStyle.chat.finalized("大丈夫かな？"), "大丈夫かな？")
        XCTAssertEqual(PolishStyle.standard.finalized("了解です。"), "了解です。")
        XCTAssertEqual(PolishStyle.mail.finalized("承知しました。"), "承知しました。")
    }

    func testInstructionsShowHowToHandleARestatement() {
        // Measured: the on-device model dropped "来週の" along with the corrected word.
        let prompt = PolishPrompt.system(dictionary: [])
        XCTAssertTrue(prompt.contains("来週の火曜日の、あ、じゃなくて水曜日"))
        XCTAssertTrue(prompt.contains("来週の水曜日"))
    }
}
