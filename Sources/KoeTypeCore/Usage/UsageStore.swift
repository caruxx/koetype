import Foundation

public struct PolishUsage: Equatable, Sendable {
    public var inputTokens: Int
    public var outputTokens: Int

    public init(inputTokens: Int, outputTokens: Int) {
        self.inputTokens = inputTokens; self.outputTokens = outputTokens
    }
}

public struct MonthlyUsage: Codable, Equatable, Sendable {
    /// "yyyy-MM" in the store's time zone.
    public var month: String
    public var requests: Int
    public var inputTokens: Int
    public var outputTokens: Int

    public init(month: String, requests: Int, inputTokens: Int, outputTokens: Int) {
        self.month = month; self.requests = requests
        self.inputTokens = inputTokens; self.outputTokens = outputTokens
    }

    public func estimatedYen(inputDollarsPerMillion: Double, outputDollarsPerMillion: Double,
                             yenPerDollar: Double) -> Double {
        let dollars = Double(inputTokens) / 1_000_000 * inputDollarsPerMillion
            + Double(outputTokens) / 1_000_000 * outputDollarsPerMillion
        return dollars * yenPerDollar
    }
}

/// Running totals of model usage per calendar month.
public final class UsageStore: @unchecked Sendable {
    public static let didChange = Notification.Name("KoeTypeUsageDidChange")

    private let file: JSONFileStore<MonthlyUsage>
    private let calendar: Calendar
    private let lock = NSLock()
    private var months: [MonthlyUsage]

    public init(fileURL: URL, timeZone: TimeZone = .current) {
        file = JSONFileStore(fileURL: fileURL)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.calendar = calendar
        months = file.load()
    }

    public func record(_ usage: PolishUsage, at date: Date) throws {
        let key = monthKey(for: date)
        try lock.withLock {
            var next = months
            if let index = next.firstIndex(where: { $0.month == key }) {
                next[index].requests += 1
                next[index].inputTokens += usage.inputTokens
                next[index].outputTokens += usage.outputTokens
            } else {
                next.append(MonthlyUsage(month: key, requests: 1,
                                         inputTokens: usage.inputTokens, outputTokens: usage.outputTokens))
            }
            try file.save(next)
            months = next
        }
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    public func month(containing date: Date) -> MonthlyUsage {
        let key = monthKey(for: date)
        return lock.withLock { months.first { $0.month == key } }
            ?? MonthlyUsage(month: key, requests: 0, inputTokens: 0, outputTokens: 0)
    }

    private func monthKey(for date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }
}
