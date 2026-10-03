import Foundation

public enum PolishValidator {
    public static func accept(polished: String, raw: String) -> String? {
        let cleaned = PolishPrompt.stripTags(polished).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        guard cleaned.count <= max(raw.count * 2, raw.count + 10) else { return nil }
        guard sharedFraction(of: cleaned, with: raw) >= minimumSharedFraction else { return nil }
        return cleaned
    }

    /// A cleaned-up transcript keeps most of the spoken characters. A translation or an
    /// answer to a dictated question does not.
    static let minimumSharedFraction = 0.4

    /// Fraction of the characters in `text` that also occur in `reference`, ignoring
    /// punctuation, character width and the hiragana/katakana distinction.
    static func sharedFraction(of text: String, with reference: String) -> Double {
        func normalized(_ value: String) -> [Character] {
            let folded = value.precomposedStringWithCompatibilityMapping
                .applyingTransform(.hiraganaToKatakana, reverse: false) ?? value
            return Array(HallucinationFilter.core(of: folded.lowercased()))
        }
        let characters = normalized(text)
        guard !characters.isEmpty else { return 0 }
        var available: [Character: Int] = [:]
        for character in normalized(reference) { available[character, default: 0] += 1 }
        var shared = 0
        for character in characters where available[character, default: 0] > 0 {
            available[character]! -= 1
            shared += 1
        }
        return Double(shared) / Double(characters.count)
    }

    public static func timeoutSeconds(forCharacterCount count: Int) -> Double {
        min(15, 3 + Double(count / 200))
    }
}
