import Foundation

/// Cleanup that needs no model: removes hesitation sounds that are never real words.
public enum LocalCleanup {
    /// Fillers safe to remove wherever they appear.
    private static let anywhere = try! NSRegularExpression(
        pattern: "(えーっと|えーと|えっと|あのー+|あのう|うーん+)[、,\\s]*")
    /// Fillers that are only safe at the start of a phrase ("へえー" must survive).
    private static let atPhraseStart = try! NSRegularExpression(
        pattern: "(^|(?<=[、。！？!?\\s]))(えー+|んー+|あの(?=[、,]))[、,\\s]*")

    public static func clean(_ text: String) -> String {
        var result = text
        // Twice: removing one filler can expose another at the start of the phrase.
        for expression in [anywhere, atPhraseStart, atPhraseStart] {
            result = expression.stringByReplacingMatches(
                in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        while let first = result.first, "、,".contains(first) { result.removeFirst() }
        return HallucinationFilter.core(of: result).isEmpty ? "" : result
    }
}

public enum PolishDecision {
    /// Short utterances are already fine after local cleanup; only longer ones are worth
    /// the cost and delay of a model call. Punctuation does not count toward the length.
    public static func shouldUseAI(for text: String, minimumCharacters: Int) -> Bool {
        HallucinationFilter.core(of: text).count >= minimumCharacters
    }
}
