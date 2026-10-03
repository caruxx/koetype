import Foundation
import KoeTypeCore

/// Runs a command-line tool with a time limit.
struct ProcessRunner: CommandRunning {
    func run(executable: String, arguments: [String], timeout: Double) async throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        // Apps launched from Finder get a minimal PATH; the Codex CLI is a script that needs `node`.
        var environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        environment["PATH"] = "\(home)/.npm-global/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:"
            + (environment["PATH"] ?? "")
        process.environment = environment
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        // The CLI reads standard input when it is not a terminal and would wait forever on an open pipe.
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        return try await withCheckedThrowingContinuation { continuation in
            let lock = NSLock()
            var finished = false
            @Sendable func finish(_ result: Result<Int32, Error>) {
                let first: Bool = lock.withLock { if finished { return false }; finished = true; return true }
                if first { continuation.resume(with: result) }
            }
            process.terminationHandler = { finish(.success($0.terminationStatus)) }
            do {
                try process.run()
            } catch {
                finish(.failure(PolishError.badResponse))
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                guard process.isRunning else { return }
                finish(.failure(PolishError.timeout))
                process.terminate()
            }
        }
    }
}

/// Sends each request to whichever service is selected in settings at that moment.
struct BackendPolisher: Polishing {
    let openAI: Polishing
    let codex: Polishing
    let usesCodex: @Sendable () -> Bool

    func polish(raw: String, dictionary: [DictionaryEntry]) async throws -> String {
        try await (usesCodex() ? codex : openAI).polish(raw: raw, dictionary: dictionary)
    }
}
