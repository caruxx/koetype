import Foundation

public struct DictionaryEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    /// Correct spelling.
    public var term: String
    /// Readings or common misrecognitions.
    public var variants: [String]
    public var createdAt: Date

    public init(id: UUID = UUID(), term: String, variants: [String] = [], createdAt: Date = Date()) {
        self.id = id; self.term = term; self.variants = variants; self.createdAt = createdAt
    }
}

public enum DictionaryError: Error, Equatable { case emptyTerm, duplicate }

public final class DictionaryStore: @unchecked Sendable {
    public static let didChange = Notification.Name("KoeTypeDictionaryDidChange")

    private let file: JSONFileStore<DictionaryEntry>
    private let lock = NSLock()
    private var stored: [DictionaryEntry]

    public init(fileURL: URL) {
        file = JSONFileStore(fileURL: fileURL)
        stored = file.load().sorted { $0.createdAt > $1.createdAt }
    }

    /// Newest first.
    public var entries: [DictionaryEntry] { lock.withLock { stored } }

    @discardableResult
    public func add(term: String, variants: [String], now: Date) throws -> DictionaryEntry {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DictionaryError.emptyTerm }
        let entry = DictionaryEntry(term: trimmed, variants: variants, createdAt: now)
        try mutate { entries in
            guard !entries.contains(where: { $0.term == trimmed }) else { throw DictionaryError.duplicate }
            entries.append(entry)
        }
        return entry
    }

    public func update(_ entry: DictionaryEntry) throws {
        var updated = entry
        updated.term = entry.term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !updated.term.isEmpty else { throw DictionaryError.emptyTerm }
        try mutate { entries in
            guard !entries.contains(where: { $0.term == updated.term && $0.id != updated.id }) else {
                throw DictionaryError.duplicate
            }
            guard let index = entries.firstIndex(where: { $0.id == updated.id }) else { return }
            entries[index] = updated
        }
    }

    public func remove(id: UUID) throws {
        try mutate { $0.removeAll { $0.id == id } }
    }

    /// Terms joined by "、", newest first, never longer than `maxCharacters`.
    public func hintText(maxCharacters: Int) -> String {
        var hint = ""
        for entry in entries {
            let candidate = hint.isEmpty ? entry.term : hint + "、" + entry.term
            if candidate.count > maxCharacters { break }
            hint = candidate
        }
        return hint
    }

    private func mutate(_ change: (inout [DictionaryEntry]) throws -> Void) throws {
        try lock.withLock {
            var next = stored
            try change(&next)
            next.sort { $0.createdAt > $1.createdAt }
            try file.save(next)
            stored = next
        }
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}
