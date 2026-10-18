import Foundation

public enum JSONFileStoreError: Error, Equatable {
    /// The existing file could not be read or set aside, so writing would destroy it.
    case unsafeToOverwrite
}

public final class JSONFileStore<Element: Codable>: @unchecked Sendable {
    public let fileURL: URL
    private let lock = NSLock()
    private var blocked = false

    public init(fileURL: URL) { self.fileURL = fileURL }

    /// Missing file -> empty. Corrupt file -> moved aside, empty.
    /// A file that exists but cannot be read or moved stays where it is and blocks `save`.
    public func load() -> [Element] {
        lock.withLock {
            blocked = false
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
            guard let data = try? Data(contentsOf: fileURL) else {
                blocked = true
                return []
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let decoded = try? decoder.decode([Element].self, from: data) { return decoded }
            blocked = !moveAside()
            return []
        }
    }

    public func save(_ elements: [Element]) throws {
        try lock.withLock {
            guard !blocked else { throw JSONFileStoreError.unsafeToOverwrite }
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(elements).write(to: fileURL, options: .atomic)
        }
    }

    private func moveAside() -> Bool {
        let directory = fileURL.deletingLastPathComponent()
        let base = "\(fileURL.lastPathComponent).corrupt-\(Int(Date().timeIntervalSince1970))"
        for suffix in ["", "-\(UUID().uuidString.prefix(8))"] {
            let target = directory.appendingPathComponent(base + suffix)
            if (try? FileManager.default.moveItem(at: fileURL, to: target)) != nil { return true }
        }
        return false
    }
}
