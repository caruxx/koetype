import Foundation

public enum PolishValidator {
    public static func accept(polished: String, raw: String) -> String? {
        let cleaned = polished
            .replacingOccurrences(of: "<transcript>", with: "")
            .replacingOccurrences(of: "</transcript>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        guard cleaned.count <= max(raw.count * 2, raw.count + 10) else { return nil }
        return cleaned
    }

    public static func timeoutSeconds(forCharacterCount count: Int) -> Double {
        min(15, 3 + Double(count / 200))
    }
}
