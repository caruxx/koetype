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
            let repoID = repo ?? "argmaxinc/whisperkit-coreml"
            let local = AppPaths.modelsDirectory
                .appendingPathComponent("models").appendingPathComponent(repoID).appendingPathComponent(model)
            let onDisk = FileManager.default.fileExists(
                atPath: local.appendingPathComponent("AudioEncoder.mlmodelc").path)
            if !onDisk { await set(.downloading(0)) }
            // Downloading always contacts the network, so skip it when the model is already here:
            // the app must start without a connection.
            let folder = onDisk ? local : try await WhisperKit.download(
                variant: model, downloadBase: AppPaths.modelsDirectory,
                from: repoID,
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
                                      skipSpecialTokens: true, withoutTimestamps: false,
                                      promptTokens: promptTokens)
        let padded = AudioPadding.withTrailingSilence(samples, sampleRate: 16_000, seconds: 1.2)
        let results = try await whisperKit.transcribe(audioArray: padded, decodeOptions: options)
        let segments = results.flatMap(\.segments).map {
            SpeechSegment(text: $0.text, start: Double($0.start))
        }
        if ProcessInfo.processInfo.environment["KOETYPE_DEBUG_SEGMENTS"] != nil {
            for segment in results.flatMap(\.segments) {
                FileHandle.standardError.write(Data(
                    String(format: "segment %.2f-%.2f %@\n", segment.start, segment.end, segment.text).utf8))
            }
        }
        return HallucinationFilter.join(segments, speechEnd: Double(samples.count) / 16_000)
    }

    @MainActor private func set(_ newState: State) { state = newState }
}
