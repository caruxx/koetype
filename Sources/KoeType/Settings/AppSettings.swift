import AppKit
import Combine
import KoeTypeCore

enum AppPaths {
    static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KoeType", isDirectory: true)
    }
    static var historyFile: URL { supportDirectory.appendingPathComponent("history.json") }
    static var dictionaryFile: URL { supportDirectory.appendingPathComponent("dictionary.json") }
    static var usageFile: URL { supportDirectory.appendingPathComponent("usage.json") }
    static var modelsDirectory: URL { supportDirectory.appendingPathComponent("Models", isDirectory: true) }
}

enum HotkeyChoice: String, CaseIterable, Identifiable {
    case rightOption, rightCommand, rightControl, fn

    var id: String { rawValue }

    var keyCode: UInt16 {
        switch self {
        case .rightOption: return 61
        case .rightCommand: return 54
        case .rightControl: return 62
        case .fn: return 63
        }
    }

    /// Bit in the raw event flags that is set only while this key itself is down.
    var deviceMask: UInt64 {
        switch self {
        case .rightOption: return 0x40
        case .rightCommand: return 0x10
        case .rightControl: return 0x2000
        case .fn: return 0x800000
        }
    }

    var label: String {
        switch self {
        case .rightOption: return "右 Option"
        case .rightCommand: return "右 Command"
        case .rightControl: return "右 Control"
        case .fn: return "Fn"
        }
    }
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    static let defaultWhisperModel = "openai_whisper-large-v3-v20240930_turbo_632MB"
    /// OpenAI's most economical model; confirmed against the official model page on 2026-10-03.
    static let defaultPolishModel = "gpt-6-luna"
    static let defaultMinimumAICharacters = 20
    /// Models the Codex CLI accepts with a ChatGPT plan differ from the API; measured on 2026-10-03.
    static let defaultCodexModel = "gpt-5.6-luna"
    /// The Codex CLI is installed by npm or Homebrew depending on the machine; use the first one found.
    static var codexPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = ["\(home)/.npm-global/bin/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? candidates[0]
    }
    /// Published list price of the default model, used only for the cost estimate shown in settings.
    static let estimateInputDollarsPerMillion = 0.10
    static let estimateOutputDollarsPerMillion = 0.50
    static let estimateYenPerDollar = 150.0

    private let defaults = UserDefaults.standard

    @Published var hotkey: HotkeyChoice { didSet { defaults.set(hotkey.rawValue, forKey: "hotkey") } }
    @Published var whisperModel: String { didSet { defaults.set(whisperModel, forKey: "whisperModel") } }
    @Published var polishEnabled: Bool { didSet { defaults.set(polishEnabled, forKey: "polishEnabled") } }
    @Published var polishModel: String { didSet { defaults.set(polishModel, forKey: "polishModel") } }
    /// Utterances shorter than this are finished locally even when AI polishing is on.
    @Published var minimumAICharacters: Int {
        didSet { defaults.set(minimumAICharacters, forKey: "minimumAICharacters") }
    }
    /// Which service performs AI polishing.
    @Published var polishBackend: PolishBackend { didSet { defaults.set(polishBackend.rawValue, forKey: "polishBackend") } }
    /// The user's own app-to-style choices, on top of the built-in rules.
    @Published var appStyleOverrides: [String: PolishStyle] {
        didSet { defaults.set(AppStyleRules.encode(appStyleOverrides), forKey: "appStyles") }
    }
    @Published var codexModel: String { didSet { defaults.set(codexModel, forKey: "codexModel") } }
    @Published var launchAtLogin: Bool { didSet { defaults.set(launchAtLogin, forKey: "launchAtLogin") } }

    private init() {
        hotkey = defaults.string(forKey: "hotkey").flatMap(HotkeyChoice.init(rawValue:)) ?? .rightCommand
        whisperModel = defaults.string(forKey: "whisperModel") ?? Self.defaultWhisperModel
        // Local processing is the default; AI polishing is an opt-in for higher accuracy.
        polishEnabled = defaults.object(forKey: "polishEnabled") as? Bool ?? false
        minimumAICharacters = defaults.object(forKey: "minimumAICharacters") as? Int ?? Self.defaultMinimumAICharacters
        polishModel = defaults.string(forKey: "polishModel") ?? Self.defaultPolishModel
        polishBackend = PolishBackend.current
        appStyleOverrides = AppStyleRules.decode(defaults.dictionary(forKey: "appStyles") as? [String: String] ?? [:])
        codexModel = defaults.string(forKey: "codexModel") ?? Self.defaultCodexModel
        launchAtLogin = defaults.bool(forKey: "launchAtLogin")
    }
}
