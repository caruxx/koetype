import Foundation

public protocol CommandRunning: Sendable {
    /// Runs a command to completion and returns its exit status. Throws `PolishError.timeout` when it takes too long.
    func run(executable: String, arguments: [String], timeout: Double) async throws -> Int32
}

/// Polishes text through the Codex CLI, which is billed to the ChatGPT plan instead of the API.
/// Slower than the API (several seconds per request) because the CLI starts a full agent session.
public final class CodexPolisher: Polishing, @unchecked Sendable {
    private let executable: @Sendable () -> String
    private let model: @Sendable () -> String
    private let runner: CommandRunning
    private let timeout: Double

    public init(executable: @escaping @Sendable () -> String, model: @escaping @Sendable () -> String,
                runner: CommandRunning, timeout: Double = 20) {
        self.executable = executable; self.model = model; self.runner = runner; self.timeout = timeout
    }

    public func polish(raw: String, dictionary: [DictionaryEntry], style: PolishStyle) async throws -> String {
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("koetype-codex-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: output) }
        let prompt = [
            PolishPrompt.system(dictionary: dictionary, style: style),
            "- ファイルの読み書きやコマンドの実行は一切しない。清書した本文だけを返す。",
            "",
            PolishPrompt.user(raw: raw),
        ].joined(separator: "\n")
        let status = try await runner.run(
            executable: executable(),
            arguments: ["exec", "--skip-git-repo-check", "--ephemeral", "--ignore-user-config", "--ignore-rules",
                        "-s", "read-only", "-m", model(), "-c", "model_reasoning_effort=low",
                        "--output-last-message", output.path, prompt],
            timeout: timeout)
        guard status == 0, let data = try? Data(contentsOf: output),
              let text = String(data: data, encoding: .utf8) else { throw PolishError.badResponse }
        return text
    }
}
