public struct AudioInputDevice: Equatable, Sendable, Identifiable {
    public var uid: String
    public var name: String
    public var isBuiltIn: Bool

    public var id: String { uid }

    public init(uid: String, name: String, isBuiltIn: Bool) {
        self.uid = uid; self.name = name; self.isBuiltIn = isBuiltIn
    }
}

/// Which microphone dictation listens to.
public enum MicrophonePreference: Hashable, Sendable {
    /// Whatever macOS currently uses for input.
    case systemDefault
    /// The Mac's own microphone, even while a headset is connected.
    case builtIn
    case device(uid: String)

    public init(stored: String?) {
        switch stored {
        case nil, "system": self = .systemDefault
        case "builtIn": self = .builtIn
        case let uid?: self = .device(uid: uid)
        }
    }

    public var stored: String {
        switch self {
        case .systemDefault: return "system"
        case .builtIn: return "builtIn"
        case .device(let uid): return uid
        }
    }

    /// The device to force, or nil to leave the choice to macOS (also when the wanted device is not connected).
    public func resolve(among devices: [AudioInputDevice]) -> AudioInputDevice? {
        switch self {
        case .systemDefault: return nil
        case .builtIn: return devices.first { $0.isBuiltIn }
        case .device(let uid): return devices.first { $0.uid == uid }
        }
    }
}
