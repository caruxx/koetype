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
            // The microphone is optional: a video can be transcribed without it.
            try? microphone.start()
            state = .recording(since: Date())
        }
    }

    func stop() {
        guard case .recording(let since) = state else { return }
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
            let file = Self.folder.appendingPathComponent(TranscriptFormatter.fileName(title: title, startedAt: startedAt))
            try Data(text.utf8).write(to: file, options: .atomic)
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
