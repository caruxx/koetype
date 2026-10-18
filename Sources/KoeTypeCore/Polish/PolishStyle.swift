import Foundation

/// How dictated text should read, chosen from the app that receives it.
public enum PolishStyle: String, Codable, CaseIterable, Sendable {
    /// Clean up, keep the speaker's own register.
    case standard
    /// Chat apps: keep it conversational.
    case chat
    /// Mail: polite written Japanese.
    case mail
    /// Terminals and editors: local cleanup only, never sent to a model.
    case minimal

    public var label: String {
        switch self {
        case .standard: return "標準"
        case .chat: return "チャット（くだけた文）"
        case .mail: return "メール（丁寧な文）"
        case .minimal: return "整形しない"
        }
    }

    /// Applies the parts of a style that must hold whatever the model returned.
    public func finalized(_ text: String) -> String {
        guard self == .chat, text.hasSuffix("。") else { return text }
        return String(text.dropLast())
    }

    /// Extra instruction lines for the model. These take priority over the general rules.
    var promptLines: [String] {
        switch self {
        case .standard, .minimal:
            return []
        case .chat:
            return ["- 宛先はチャットです。話し言葉の調子をそのまま保つ。文の途中の句読点は付けるが、最後の文の末尾の「。」は付けない。"]
        case .mail:
            return ["- 宛先はメールです。です・ます調の丁寧な書き言葉に整える。この規則は「言い換えない」より優先するが、伝える内容は変えない。"]
        }
    }
}

public struct AppStyleRules: Sendable {
    /// Styles that suit well-known apps without any setup, keyed by bundle identifier.
    public static let builtIn: [String: PolishStyle] = [
        "com.tinyspeck.slackmacgap": .chat,
        "jp.naver.line.mac": .chat,
        "com.hnc.Discord": .chat,
        "com.apple.MobileSMS": .chat,
        "com.microsoft.teams2": .chat,
        "net.whatsapp.WhatsApp": .chat,
        "com.apple.mail": .mail,
        "com.microsoft.Outlook": .mail,
        "com.readdle.smartemail-Mac": .mail,
        "com.apple.Terminal": .minimal,
        "com.googlecode.iterm2": .minimal,
        "dev.warp.Warp-Stable": .minimal,
        "com.mitchellh.ghostty": .minimal,
        "com.microsoft.VSCode": .minimal,
        "com.apple.dt.Xcode": .minimal,
    ]

    private let overrides: [String: PolishStyle]

    public init(overrides: [String: PolishStyle]) { self.overrides = overrides }

    /// Built-in rules with the user's choices applied on top.
    public var all: [String: PolishStyle] { Self.builtIn.merging(overrides) { _, chosen in chosen } }

    public func style(forBundleID bundleID: String?) -> PolishStyle {
        guard let bundleID else { return .standard }
        return overrides[bundleID] ?? Self.builtIn[bundleID] ?? .standard
    }

    public static func encode(_ overrides: [String: PolishStyle]) -> [String: String] {
        overrides.mapValues(\.rawValue)
    }

    public static func decode(_ stored: [String: String]) -> [String: PolishStyle] {
        stored.compactMapValues(PolishStyle.init(rawValue:))
    }
}
