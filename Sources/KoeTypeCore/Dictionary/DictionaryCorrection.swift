import Foundation
import NaturalLanguage

/// Explicit aliases only. Use original-text boundaries and never scan replacement output.
public enum DictionaryCorrection {
    public static func apply(to text: String, entries: [DictionaryEntry]) -> String {
        guard !text.isEmpty else { return text }
        let terms = Set(entries.map { $0.term.trimmingCharacters(in: .whitespacesAndNewlines) })
        var destinations: [String: Set<String>] = [:]
        for entry in entries {
            let term = entry.term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty else { continue }
            for variant in entry.variants {
                let alias = variant.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !alias.isEmpty, alias != term, !terms.contains(alias) else { continue }
                destinations[alias, default: []].insert(term)
            }
        }
        let rules = destinations.compactMap { alias, targets -> (String, String)? in
            guard targets.count == 1, let target = targets.first else { return nil }
            return (alias, target)
        }.sorted { $0.0.count == $1.0.count ? $0.0 < $1.0 : $0.0.count > $1.0.count }
        guard !rules.isEmpty else { return text }

        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var starts = Set<String.Index>(), ends = Set<String.Index>()
        var tokenStarting: [String.Index: String] = [:], tokenEnding: [String.Index: String] = [:]
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            starts.insert(range.lowerBound); ends.insert(range.upperBound)
            let token = String(text[range])
            tokenStarting[range.lowerBound] = token; tokenEnding[range.upperBound] = token
            return true
        }
        // A canonical spelling must not be rewritten by an alias contained in it.
        var protected: [Range<String.Index>] = []
        for term in terms where !term.isEmpty {
            var cursor = text.startIndex
            while cursor < text.endIndex,
                  let range = text.range(of: term, options: .literal, range: cursor..<text.endIndex) {
                protected.append(range)
                cursor = text.index(after: range.lowerBound)
            }
        }
        // Preserve literal URLs, addresses, handles, and code-like spans even when
        // NaturalLanguage tokenizes an alias inside them as a standalone word.
        let patterns = [
            #"(?:[A-Za-z][A-Za-z0-9+.-]*://|www\.)[^\s<>"「」]+"#,
            #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#,
            #"(?<![\p{L}\p{N}_])[@#][A-Za-z0-9_]+"#,
            #"(?s)```.*?```|`[^`\n]*`"#,
            #"(?:[A-Za-z0-9_]+[._/+#:\\-]+)+[A-Za-z0-9_]+"#,
            #"[A-Za-z_][A-Za-z0-9_]*\s*\("#,
            #"--?[A-Za-z][A-Za-z0-9_-]*"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let range = Range(match.range, in: text) { protected.append(range) }
            }
        }
        func isASCIIWord(_ character: Character) -> Bool {
            character.unicodeScalars.allSatisfy {
                $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "_")
            }
        }
        func isJapanese(_ character: Character) -> Bool {
            character.unicodeScalars.contains {
                (0x3040...0x30ff).contains($0.value) || (0x3400...0x9fff).contains($0.value)
                || (0xff66...0xff9f).contains($0.value) || (0x20000...0x3134f).contains($0.value)
            }
        }
        // Tokenization may split proper-name compounds such as 東京大学. Only an
        // independent token or an adjacent standalone particle is safe for Japanese aliases.
        let particles: Set<String> = ["を", "は", "が", "に", "の", "で", "と", "も", "へ", "から", "まで", "より"]
        func safeBoundary(_ range: Range<String.Index>, alias: String) -> Bool {
            if let first = alias.first, range.lowerBound > text.startIndex {
                let prior = text.index(before: range.lowerBound)
                if isJapanese(first), isJapanese(text[prior]),
                   !particles.contains(tokenEnding[range.lowerBound] ?? "") { return false }
                if isASCIIWord(first) {
                    if isASCIIWord(text[prior]) { return false }
                    if "-.+#/'".contains(text[prior]), prior > text.startIndex,
                       isASCIIWord(text[text.index(before: prior)]) { return false }
                }
            }
            if let last = alias.last, range.upperBound < text.endIndex {
                let next = range.upperBound
                if isJapanese(last), isJapanese(text[next]),
                   !particles.contains(tokenStarting[next] ?? "") { return false }
                if isASCIIWord(last) {
                    if isASCIIWord(text[next]) { return false }
                    let after = text.index(after: next)
                    if "-.+#/'".contains(text[next]), after < text.endIndex,
                       isASCIIWord(text[after]) { return false }
                }
            }
            return true
        }
        var result = "", cursor = text.startIndex
        while cursor < text.endIndex {
            var replacement: (Range<String.Index>, String)?
            for (alias, term) in rules {
                guard text[cursor...].hasPrefix(alias) else { continue }
                let end = text.index(cursor, offsetBy: alias.count)
                let range = cursor..<end
                guard starts.contains(cursor), ends.contains(end),
                      !protected.contains(where: { $0.overlaps(range) }) else { continue }
                guard safeBoundary(range, alias: alias) else { continue }
                replacement = (range, term)
                break
            }
            if let (range, term) = replacement {
                result += term
                cursor = range.upperBound
            } else {
                result.append(text[cursor])
                cursor = text.index(after: cursor)
            }
        }
        return result
    }
}
