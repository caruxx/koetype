import Foundation

public actor DictationPipeline {
    /// One queued recording. The closure holds the pipeline strongly, so a pipeline
    /// with pending work stays alive until that work has been delivered.
    private typealias Job = @Sendable () async -> Void

    private let transcriber: Transcribing
    private let polisher: Polishing
    private let deliverer: TextDelivering
    private let dictionary: DictionaryStore
    private let history: HistoryStore
    private let polishEnabled: @Sendable () -> Bool
    private let hintLimit: Int
    private let now: @Sendable () -> Date
    private let onStatus: @Sendable (PipelineStatus) -> Void
    private nonisolated let jobs: AsyncStream<Job>.Continuation

    public init(transcriber: Transcribing, polisher: Polishing, deliverer: TextDelivering,
                dictionary: DictionaryStore, history: HistoryStore,
                polishEnabled: @escaping @Sendable () -> Bool,
                hintLimit: Int = 120,
                now: @escaping @Sendable () -> Date = Date.init,
                onStatus: @escaping @Sendable (PipelineStatus) -> Void = { _ in }) {
        self.transcriber = transcriber; self.polisher = polisher; self.deliverer = deliverer
        self.dictionary = dictionary; self.history = history
        self.polishEnabled = polishEnabled; self.hintLimit = hintLimit
        self.now = now; self.onStatus = onStatus
        let (stream, continuation) = AsyncStream<Job>.makeStream()
        self.jobs = continuation
        Task {
            for await job in stream { await job() }
        }
    }

    deinit { jobs.finish() }

    @discardableResult
    public nonisolated func submit(samples: [Float], durationSeconds: Double) -> Task<Void, Never> {
        let (signal, finish) = AsyncStream<Void>.makeStream()
        jobs.yield {
            await self.process(samples: samples, durationSeconds: durationSeconds)
            finish.finish()
        }
        return Task { for await _ in signal {} }
    }

    private func process(samples: [Float], durationSeconds: Double) async {
        onStatus(.transcribing)
        let transcript: String
        do {
            transcript = try await transcriber.transcribe(
                samples: samples, hints: dictionary.hintText(maxCharacters: hintLimit))
        } catch {
            onStatus(.failed("文字起こしに失敗しました"))
            return
        }
        let raw = HallucinationFilter.clean(transcript)
        guard !raw.isEmpty else {
            onStatus(.nothingHeard)
            return
        }

        var finalText = raw
        var polished = false
        if polishEnabled() {
            onStatus(.polishing)
            if let result = try? await polisher.polish(raw: raw, dictionary: dictionary.entries),
               let accepted = PolishValidator.accept(polished: result, raw: raw) {
                finalText = accepted
                polished = true
            }
        }

        let delivery = await deliverer.deliver(finalText)
        try? history.append(HistoryItem(date: now(), rawText: raw, finalText: finalText,
                                        appName: delivery.appName, outcome: delivery.outcome,
                                        polished: polished, durationSeconds: durationSeconds))
        onStatus(.delivered(delivery.outcome, polished: polished))
    }
}
