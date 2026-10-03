import Foundation
import WhisperKit
import KoeTypeCore

enum TranscriberError: Error { case notReady }

final class WhisperKitTranscriber: Transcribing, ObservableObject, @unchecked Sendable {
    enum State: Equatable { case notLoaded, downloading(Double), loading, ready, failed(String) }

    /// Example of punctuated Japanese given to the decoder as preceding context,
    /// which makes it far more consistent about writing "、" and "。".
    static let punctuationPrimer = "こんにちは。今日は、よろしくお願いします。"

    @Published private(set) var state: State = .notLoaded

    private let lock = NSLock()
    private var whisperKit: WhisperKit?
    /// Identifies the most recent `load` call; an older call that finishes later is discarded.
    private var generation = 0
    private let gate = AsyncGate()

    /// True while a model is available, even if a later reload failed.
    var isReady: Bool { lock.withLock { whisperKit != nil } }

    /// `repo` selects a Hugging Face repository other than WhisperKit's default one.
    func load(model: String, repo: String? = nil) async {
        let mine: Int = lock.withLock { generation += 1; return generation }
        do {
            try FileManager.default.createDirectory(at: AppPaths.modelsDirectory, withIntermediateDirectories: true)
            let repoID = repo ?? "argmaxinc/whisperkit-coreml"
            let local = AppPaths.modelsDirectory
                .appendingPathComponent("models").appendingPathComponent(repoID).appendingPathComponent(model)
            let onDisk = FileManager.default.fileExists(
                atPath: local.appendingPathComponent("AudioEncoder.mlmodelc").path)
            if !onDisk { await set(.downloading(0), for: mine) }
            // Downloading always contacts the network, so skip it when the model is already here:
            // the app must start without a connection.
            let folder = onDisk ? local : try await WhisperKit.download(
                variant: model, downloadBase: AppPaths.modelsDirectory,
                from: repoID,
                progressCallback: { [weak self] progress in
                    Task { await self?.set(.downloading(progress.fractionCompleted), for: mine) }
                })
            await set(.loading, for: mine)
            let config = WhisperKitConfig(model: model, modelFolder: folder.path,
                                          verbose: false, prewarm: true, load: true, download: false)
            let loaded = try await WhisperKit(config)
            let current = lock.withLock { () -> Bool in
                guard generation == mine else { return false }
                whisperKit = loaded
                return true
            }
            if current { await set(.ready, for: mine) }
        } catch {
            // A model that was already working stays in use.
            await set(.failed(error.localizedDescription), for: mine)
        }
    }

    func transcribe(samples: [Float], hints: String) async throws -> String {
        try await segments(samples: samples, hints: hints).map(\.text).joined()
    }

    /// Transcribes a long recording in pieces of about five minutes, cut at quiet moments.
    /// Dictation requests can run between the pieces. `progress` receives 0...1.
    func transcribeLong(samples: [Float], hints: String,
                        progress: @escaping @Sendable (Double) -> Void) async throws -> [SpeechSegment] {
        let ranges = AudioChunker.ranges(for: samples, sampleRate: 16_000, targetSeconds: 300, searchSeconds: 15)
        var all: [SpeechSegment] = []
        for (index, range) in ranges.enumerated() {
            let offset = Double(range.lowerBound) / 16_000
            let part = try await segments(samples: Array(samples[range]), hints: hints)
            all.append(contentsOf: part.map { SpeechSegment(text: $0.text, start: $0.start + offset) })
            progress(Double(index + 1) / Double(ranges.count))
        }
        return all
    }

    private func segments(samples: [Float], hints: String) async throws -> [SpeechSegment] {
        guard let whisperKit = lock.withLock({ self.whisperKit }) else { throw TranscriberError.notReady }
        // One decode at a time: the model is shared between dictation and long recordings.
        await gate.acquire()
        defer { gate.release() }
        var promptTokens: [Int]?
        if let tokenizer = whisperKit.tokenizer {
            let context = hints.isEmpty ? Self.punctuationPrimer : Self.punctuationPrimer + hints + "。"
            promptTokens = tokenizer.encode(text: " " + context)
                .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
        }
        let options = DecodingOptions(task: .transcribe, language: "ja", temperature: 0,
                                      usePrefillPrompt: true, detectLanguage: false,
                                      skipSpecialTokens: true, withoutTimestamps: false,
                                      promptTokens: promptTokens)
        let padded = AudioPadding.withTrailingSilence(samples, sampleRate: 16_000, seconds: 1.2)
        let results = try await whisperKit.transcribe(audioArray: padded, decodeOptions: options)
        if ProcessInfo.processInfo.environment["KOETYPE_DEBUG_SEGMENTS"] != nil {
            for segment in results.flatMap(\.segments) {
                FileHandle.standardError.write(Data(
                    String(format: "segment %.2f-%.2f %@\n", segment.start, segment.end, segment.text).utf8))
            }
        }
        let segments = results.flatMap(\.segments).map {
            SpeechSegment(text: $0.text, start: Double($0.start))
        }
        return HallucinationFilter.spoken(segments, speechEnd: Double(samples.count) / 16_000)
    }

    @MainActor private func set(_ newState: State, for loadGeneration: Int) {
        guard lock.withLock({ generation == loadGeneration }) else { return }
        state = newState
    }
}

/// Lets one task through at a time, in arrival order.
final class AsyncGate: @unchecked Sendable {
    private let lock = NSLock()
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let proceed: Bool = lock.withLock {
                if busy { waiters.append(continuation); return false }
                busy = true
                return true
            }
            if proceed { continuation.resume() }
        }
    }

    func release() {
        let next: CheckedContinuation<Void, Never>? = lock.withLock {
            if waiters.isEmpty { busy = false; return nil }
            return waiters.removeFirst()
        }
        next?.resume()
    }
}
