import Foundation

public enum HallucinationFilter {
    // Phrases Whisper tends to emit for silence or noise. Compared after stripping punctuation.
    static let phantoms: Set<String> = [
        "ご視聴ありがとうございました", "ご清聴ありがとうございました",
        "最後までご視聴いただきありがとうございます", "最後までご視聴いただきありがとうございました",
        "チャンネル登録お願いします", "チャンネル登録をお願いします", "チャンネル登録よろしくお願いします",
        "字幕視聴ありがとうございました", "音楽", "拍手", "笑", "無音",
    ]

    public static func clean(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let strip = CharacterSet.punctuationCharacters.union(.symbols).union(.whitespacesAndNewlines)
        let core = String(String.UnicodeScalarView(trimmed.unicodeScalars.filter { !strip.contains($0) }))
        return core.isEmpty || phantoms.contains(core) ? "" : trimmed
    }
}
