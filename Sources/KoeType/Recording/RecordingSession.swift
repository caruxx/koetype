import AppKit
import KoeTypeCore

/// Records what the Mac is playing together with the microphone, then writes a timestamped transcript.
@MainActor
final class RecordingSession: ObservableObject {
    enum State: Equatable {
        case idle
        case recording(since: Date)
        case transcribing(progress: Double)
    }

    /// Upper bound for one recording; both streams are held in memory until it ends.
    static let maxSeconds: Double = 2 * 60 * 60

    @Published private(set) var state: State = .idle
    @Published private(set) var lastError: String?

    private let transcriber: WhisperKitTranscriber
    private let dictionary: DictionaryStore
    private let system = SystemAudioRecorder()
    private let microphone = AudioRecorder()
    /// Ends the recording at `maxSeconds` by the clock. The microphone's own sample limit does the same,
    /// but the microphone is optional: with the Mac's sound alone nothing else would end it.
    private var limit: Task<Void, Never>?

    init(transcriber: WhisperKitTranscriber, dictionary: DictionaryStore) {
        self.transcriber = transcriber
        self.dictionary = dictionary
        microphone.maxSeconds = Self.maxSeconds
        microphone.onLimitReached = { [weak self] in self?.stop() }
        system.onStopped = { [weak self] in self?.stop() }
    }

    static var folder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KoeType", isDirectory: true)
    }

    var isRecording: Bool {
        if case .recording = state { return true }
        return false
    }

    func toggle() {
        isRecording ? stop() : start()
    }

    func start() {
        guard state == .idle else { return }
        guard transcriber.isReady else { return fail("モデルを準備中です") }
        lastError = nil
        Task {
            do {
                try await system.start()
            } catch {
                return fail("Mac の音を取り込めませんでした。システム設定の「画面収録とシステムオーディオ録音」で KoeType を許可してください。")
            }
            // The microphone is optional: a video can be transcribed without it, so a failure to open
            // it (reported through onInterrupted, which is not set here) is ignored.
            microphone.start()
            let since = Date()
            state = .recording(since: since)
            limit = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(Self.maxSeconds * 1_000_000_000))
                // Only the recording this timer was set for, and only once its time is really up.
                guard let self, !Task.isCancelled, case .recording(let started) = self.state, started == since,
                      RecordingLimit.reached(startedAt: started, now: Date(), maxSeconds: Self.maxSeconds) else { return }
                self.stop()
            }
        }
    }

    func stop() {
        guard case .recording(let since) = state else { return }
        limit?.cancel()
        limit = nil
        state = .transcribing(progress: 0)
        Task {
            let played = await system.stop()
            let spoken = microphone.isRecording ? microphone.stop().samples : []
            await finish(samples: AudioMixer.mix(played, spoken), title: "記録", startedAt: since)
        }
    }

    /// Transcribes an existing sound or movie file.
    func transcribe(file url: URL) {
        guard state == .idle else { return }
        guard transcriber.isReady else { return fail("モデルを準備中です") }
        lastError = nil
        state = .transcribing(progress: 0)
        Task {
            let path = url.path
            guard let samples = await Task.detached(operation: { AudioFileLoader.load(path: path) }).value else {
                state = .idle
                return fail("このファイルの音声を読み込めませんでした")
            }
            await finish(samples: samples, title: url.deletingPathExtension().lastPathComponent, startedAt: Date())
        }
    }

    private func finish(samples: [Float], title: String, startedAt: Date) async {
        defer { state = .idle }
        guard !samples.isEmpty else { return fail("音声が記録されていませんでした") }
        do {
            let segments = try await transcriber.transcribeLong(
                samples: samples, hints: dictionary.hintText(maxCharacters: 120),
                progress: { value in Task { @MainActor [weak self] in self?.state = .transcribing(progress: value) } })
            let text = TranscriptFormatter.markdown(
                title: title, startedAt: startedAt,
                durationSeconds: Double(samples.count) / AudioRecorder.sampleRate, segments: segments)
            try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
            // A transcript never replaces an earlier one: the name is made unique, and the write itself
            // refuses an existing file in case one appeared in between.
            let folder = Self.folder
            let name = TranscriptFormatter.uniqueFileName(title: title, startedAt: startedAt) { candidate in
                FileManager.default.fileExists(atPath: folder.appendingPathComponent(candidate).path)
            }
            let file = folder.appendingPathComponent(name)
            try Data(text.utf8).write(to: file, options: .withoutOverwriting)
            WindowManager.shared.showTranscript(text: text, file: file)
        } catch {
            fail("文字起こしを保存できませんでした")
        }
    }

    private func fail(_ message: String) {
        lastError = message
        WindowManager.shared.showTranscript(text: message, file: nil)
    }
}
