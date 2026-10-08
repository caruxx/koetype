import Foundation

// Keep insertedAndCopyBox so existing history remains decodable. New uncertain pastes use unverified.
public enum DeliveryOutcome: String, Codable, Sendable { case inserted, copyBox, insertedAndCopyBox, unverified, notPasted }

public struct HistoryItem: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var date: Date
    public var rawText: String
    public var finalText: String
    public var appName: String?
    public var outcome: DeliveryOutcome
    public var polished: Bool
    public var durationSeconds: Double

    private enum CodingKeys: String, CodingKey {
        case id, date, rawText, finalText, appName, outcome, polished, durationSeconds, unverified, notPasted
    }

    public init(id: UUID = UUID(), date: Date, rawText: String, finalText: String, appName: String?,
                outcome: DeliveryOutcome, polished: Bool, durationSeconds: Double) {
        self.id = id; self.date = date; self.rawText = rawText; self.finalText = finalText
        self.appName = appName; self.outcome = outcome; self.polished = polished
        self.durationSeconds = durationSeconds
    }

    public init(from decoder: Decoder) throws {
        let data = try decoder.container(keyedBy: CodingKeys.self)
        id = try data.decode(UUID.self, forKey: .id)
        date = try data.decode(Date.self, forKey: .date)
        rawText = try data.decode(String.self, forKey: .rawText)
        finalText = try data.decode(String.self, forKey: .finalText)
        appName = try data.decodeIfPresent(String.self, forKey: .appName)
        let storedOutcome = try data.decode(DeliveryOutcome.self, forKey: .outcome)
        if try data.decodeIfPresent(Bool.self, forKey: .notPasted) == true {
            outcome = .notPasted
        } else if try data.decodeIfPresent(Bool.self, forKey: .unverified) == true {
            outcome = .unverified
        } else {
            outcome = storedOutcome
        }
        polished = try data.decode(Bool.self, forKey: .polished)
        durationSeconds = try data.decode(Double.self, forKey: .durationSeconds)
    }

    public func encode(to encoder: Encoder) throws {
        var data = encoder.container(keyedBy: CodingKeys.self)
        try data.encode(id, forKey: .id)
        try data.encode(date, forKey: .date)
        try data.encode(rawText, forKey: .rawText)
        try data.encode(finalText, forKey: .finalText)
        try data.encodeIfPresent(appName, forKey: .appName)
        // Older KoeType versions do not understand the new enum case. Preserve the
        // whole history on rollback by using a known conservative outcome on disk.
        try data.encode(outcome == .unverified || outcome == .notPasted ? .copyBox : outcome, forKey: .outcome)
        if outcome == .unverified { try data.encode(true, forKey: .unverified) }
        if outcome == .notPasted { try data.encode(true, forKey: .notPasted) }
        try data.encode(polished, forKey: .polished)
        try data.encode(durationSeconds, forKey: .durationSeconds)
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
