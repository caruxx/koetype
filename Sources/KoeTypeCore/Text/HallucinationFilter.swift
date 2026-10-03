import Foundation

public enum HallucinationFilter {
    // Phrases Whisper tends to emit for silence or noise. Compared after stripping punctuation.
    static let phantoms: Set<String> = [
        "ご視聴ありがとうございました", "ご清聴ありがとうございました",
        "最後までご視聴いただきありがとうございます", "最後までご視聴いただきありがとうございました",
        "チャンネル登録お願いします", "チャンネル登録をお願いします", "チャンネル登録よろしくお願いします",
        "字幕視聴ありがとうございました", "音楽", "拍手", "笑", "無音",
    ]

    /// Closing phrases Whisper appends for trailing silence. Longer than `tailWindow` when really spoken.
    static let tailPhantoms: Set<String> = phantoms.union([
        "ありがとうございました", "ありがとうございます", "おやすみなさい", "お疲れ様でした", "では", "それでは",
    ])
    static let tailWindow = 0.5

    static func core(of text: String) -> String {
        let strip = CharacterSet.punctuationCharacters.union(.symbols).union(.whitespacesAndNewlines)
        return String(String.UnicodeScalarView(text.unicodeScalars.filter { !strip.contains($0) }))
    }

    public static func clean(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let core = core(of: trimmed)
        return core.isEmpty || phantoms.contains(core) ? "" : trimmed
    }

    /// Joins decoded segments, leaving out any that begin after the real audio ended.
    /// Silence is appended before decoding, and Whisper sometimes invents a phrase for it.
    public static func join(_ segments: [SpeechSegment], speechEnd: Double) -> String {
        segments.enumerated()
            .filter { index, segment in
                if index == 0 { return true }
                if segment.start >= speechEnd - 0.1 { return false }
                // Too little speech is left for the phrase to have been spoken.
                let squeezed = segment.start >= speechEnd - tailWindow
                return !(squeezed && tailPhantoms.contains(core(of: segment.text)))
            }
            .map { $0.element.text }
            .joined()
    }
}

public struct SpeechSegment: Equatable, Sendable {
    public var text: String
    /// Seconds from the beginning of the audio.
    public var start: Double

    public init(text: String, start: Double) {
        self.text = text; self.start = start
    }
}
