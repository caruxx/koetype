import Foundation

public enum DeliveryOutcome: String, Codable, Sendable { case inserted, copyBox, insertedAndCopyBox }

public struct HistoryItem: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var date: Date
    public var rawText: String
    public var finalText: String
    public var appName: String?
    public var outcome: DeliveryOutcome
    public var polished: Bool
    public var durationSeconds: Double

    public init(id: UUID = UUID(), date: Date, rawText: String, finalText: String, appName: String?,
                outcome: DeliveryOutcome, polished: Bool, durationSeconds: Double) {
        self.id = id; self.date = date; self.rawText = rawText; self.finalText = finalText
        self.appName = appName; self.outcome = outcome; self.polished = polished
        self.durationSeconds = durationSeconds
    }
}

public final class HistoryStore: @unchecked Sendable {
    public static let didChange = Notification.Name("KoeTypeHistoryDidChange")

    private let file: JSONFileStore<HistoryItem>
    private let limit: Int
    private let lock = NSLock()
    private var stored: [HistoryItem]

    public init(fileURL: URL, limit: Int = 1000) {
        file = JSONFileStore(fileURL: fileURL)
        self.limit = limit
        stored = Array(file.load().sorted { $0.date > $1.date }.prefix(limit))
    }

    /// Newest first.
    public var items: [HistoryItem] { lock.withLock { stored } }

    public func append(_ item: HistoryItem) throws {
        try mutate { items in
            items.insert(item, at: 0)
            if items.count > limit { items.removeLast(items.count - limit) }
        }
    }

    public func remove(id: UUID) throws {
        try mutate { $0.removeAll { $0.id == id } }
    }

    public func search(_ query: String) -> [HistoryItem] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return items }
        return items.filter {
            $0.finalText.localizedCaseInsensitiveContains(needle) || $0.rawText.localizedCaseInsensitiveContains(needle)
        }
    }

    private func mutate(_ change: (inout [HistoryItem]) throws -> Void) throws {
        try lock.withLock {
            var next = stored
            try change(&next)
            try file.save(next)
            stored = next
        }
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}
