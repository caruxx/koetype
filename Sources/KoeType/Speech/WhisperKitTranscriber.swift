import Foundation
import WhisperKit
import KoeTypeCore

enum TranscriberError: Error { case notReady }

final class WhisperKitTranscriber: Transcribing, ObservableObject, @unchecked Sendable {
    enum State: Equatable { case notLoaded, downloading(Double), loading, ready, failed(String) }

    @Published private(set) var state: State = .notLoaded
    private var whisperKit: WhisperKit?

    var isReady: Bool { whisperKit != nil }

    /// `repo` selects a Hugging Face repository other than WhisperKit's default one.
    func load(model: String, repo: String? = nil) async {
        do {
            try FileManager.default.createDirectory(at: AppPaths.modelsDirectory, withIntermediateDirectories: true)
            await set(.downloading(0))
            let folder = try await WhisperKit.download(
                variant: model, downloadBase: AppPaths.modelsDirectory,
                from: repo ?? "argmaxinc/whisperkit-coreml",
                progressCallback: { [weak self] progress in
                    Task { await self?.set(.downloading(progress.fractionCompleted)) }
                })
            await set(.loading)
            let config = WhisperKitConfig(model: model, modelFolder: folder.path,
                                          verbose: false, prewarm: true, load: true, download: false)
            whisperKit = try await WhisperKit(config)
            await set(.ready)
        } catch {
            whisperKit = nil
            await set(.failed(error.localizedDescription))
        }
    }

    func transcribe(samples: [Float], hints: String) async throws -> String {
        guard let whisperKit else { throw TranscriberError.notReady }
        var promptTokens: [Int]?
        if !hints.isEmpty, let tokenizer = whisperKit.tokenizer {
            promptTokens = tokenizer.encode(text: " " + hints)
                .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
        }
        let options = DecodingOptions(task: .transcribe, language: "ja", temperature: 0,
                                      usePrefillPrompt: true, detectLanguage: false,
                                      skipSpecialTokens: true, withoutTimestamps: true,
                                      promptTokens: promptTokens)
        let results = try await whisperKit.transcribe(audioArray: samples, decodeOptions: options)
        return results.map(\.text).joined()
    }

    @MainActor private func set(_ newState: State) { state = newState }
}
