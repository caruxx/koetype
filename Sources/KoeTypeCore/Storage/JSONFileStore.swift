import Foundation

public struct JSONFileStore<Element: Codable> {
    public let fileURL: URL
    public init(fileURL: URL) { self.fileURL = fileURL }

    public func load() -> [Element] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([Element].self, from: data) { return decoded }
        let aside = fileURL.deletingLastPathComponent().appendingPathComponent(
            "\(fileURL.lastPathComponent).corrupt-\(Int(Date().timeIntervalSince1970))")
        try? FileManager.default.moveItem(at: fileURL, to: aside)
        return []
    }

    public func save(_ elements: [Element]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(elements).write(to: fileURL, options: .atomic)
    }
}
