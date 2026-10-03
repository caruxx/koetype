import Foundation
import KoeTypeCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Polishes text with the language model built into macOS. Nothing leaves the Mac and there is no charge.
struct AppleModelPolisher: Polishing {
    /// The on-device model answers in about a second; anything much longer means it is stuck.
    var timeout: Double = 8

    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    /// Loads the model ahead of the first request so that request is not the slow one.
    static func prewarm() {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), isAvailable {
            LanguageModelSession(instructions: PolishPrompt.system(dictionary: [])).prewarm()
        }
        #endif
    }

    func polish(raw: String, dictionary: [DictionaryEntry], style: PolishStyle) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), Self.isAvailable {
            let instructions = PolishPrompt.system(dictionary: dictionary, style: style)
            let prompt = PolishPrompt.user(raw: raw)
            let seconds = timeout
            return try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask {
                    // A fresh session per utterance: earlier dictations must not colour this one.
                    let session = LanguageModelSession(instructions: instructions)
                    do {
                        return try await session.respond(to: prompt).content
                    } catch {
                        throw PolishError.badResponse
                    }
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                    throw PolishError.timeout
                }
                defer { group.cancelAll() }
                return try await group.next()!
            }
        }
        #endif
        throw PolishError.unavailable
    }
}
