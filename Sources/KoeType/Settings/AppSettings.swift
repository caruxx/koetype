import AppKit
import Combine

enum AppPaths {
    static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KoeType", isDirectory: true)
    }
    static var historyFile: URL { supportDirectory.appendingPathComponent("history.json") }
    static var dictionaryFile: URL { supportDirectory.appendingPathComponent("dictionary.json") }
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
    static let defaultPolishModel = "gpt-4.1-mini"

    private let defaults = UserDefaults.standard

    @Published var hotkey: HotkeyChoice { didSet { defaults.set(hotkey.rawValue, forKey: "hotkey") } }
    @Published var whisperModel: String { didSet { defaults.set(whisperModel, forKey: "whisperModel") } }
    @Published var polishEnabled: Bool { didSet { defaults.set(polishEnabled, forKey: "polishEnabled") } }
    @Published var polishModel: String { didSet { defaults.set(polishModel, forKey: "polishModel") } }
    @Published var launchAtLogin: Bool { didSet { defaults.set(launchAtLogin, forKey: "launchAtLogin") } }

    private init() {
        hotkey = defaults.string(forKey: "hotkey").flatMap(HotkeyChoice.init(rawValue:)) ?? .rightCommand
        whisperModel = defaults.string(forKey: "whisperModel") ?? Self.defaultWhisperModel
        polishEnabled = defaults.object(forKey: "polishEnabled") as? Bool ?? true
        polishModel = defaults.string(forKey: "polishModel") ?? Self.defaultPolishModel
        launchAtLogin = defaults.bool(forKey: "launchAtLogin")
    }
}
