import Foundation
import KoeTypeCore

/// One line per delivery describing where the text went and why. Never contains the text itself.
/// Kept so that "it did not appear" reports can be traced to what the target app reported.
enum InsertionLog {
    static var fileURL: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/KoeType/insertion.log")
    }

    static func record(app: String?, snapshot: FocusSnapshot?, plan: InsertionPlan, verified: Bool?) {
        let fields: [String]
        if let snapshot {
            fields = ["role=\(snapshot.role ?? "none")", "editable=\(snapshot.isEditable)",
                      "range=\(snapshot.hasSelectedTextRange)", "readable=\(snapshot.valueLength != nil)"]
        } else {
            fields = ["query=failed"]
        }
        let result = verified.map { "verified=\($0)" } ?? "verified=n/a"
        let line = ([ISO8601DateFormatter().string(from: Date()), "app=\(app ?? "unknown")"] + fields
            + ["plan=\(plan)", result]).joined(separator: " ") + "\n"
        let url = fileURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }
}
