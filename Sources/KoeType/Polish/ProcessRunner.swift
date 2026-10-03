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
            let once = Once()
            @Sendable func finish(_ result: Result<Int32, Error>) {
                if once.first() { continuation.resume(with: result) }
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

enum PolishBackend: String, CaseIterable, Identifiable {
    /// The model built into macOS.
    case local
    case openAI
    case codex

    var id: String { rawValue }

    var label: String {
        switch self {
        case .local: return "この Mac の中で（無料・約 1 秒）"
        case .openAI: return "OpenAI API（高精度・従量課金）"
        case .codex: return "Codex CLI（ChatGPT の利用枠・約 5 秒）"
        }
    }

    /// The backend stored in settings; older versions stored only a Codex on/off flag.
    static var current: PolishBackend {
        let defaults = UserDefaults.standard
        if let stored = defaults.string(forKey: "polishBackend"), let backend = PolishBackend(rawValue: stored) {
            return backend
        }
        return defaults.bool(forKey: "polishViaCodex") ? .codex : .local
    }
}

/// Sends each request to whichever service is selected in settings at that moment.
struct BackendPolisher: Polishing {
    let local: Polishing
    let openAI: Polishing
    let codex: Polishing
    let backend: @Sendable () -> PolishBackend

    func polish(raw: String, dictionary: [DictionaryEntry], style: PolishStyle) async throws -> String {
        let polisher: Polishing
        switch backend() {
        case .local: polisher = local
        case .openAI: polisher = openAI
        case .codex: polisher = codex
        }
        return try await polisher.polish(raw: raw, dictionary: dictionary, style: style)
    }
}

/// True exactly once, however many threads ask.
private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var used = false

    func first() -> Bool {
        lock.withLock {
            if used { return false }
            used = true
            return true
        }
    }
}
