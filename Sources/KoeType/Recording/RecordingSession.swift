import AppKit
import KoeTypeCore

/// Records what the Mac is playing together with the microphone, then writes a timestamped transcript.
@MainActor
final class RecordingSession: ObservableObject {
    enum State: Equatable {
        case idle
        /// Claimed before the sources are opened, so nothing else can begin in the meantime.
        case starting
        case recording(since: Date)
        case transcribing(progress: Double)

        var phase: RecordingSessionPhase {
            switch self {
            case .idle: return .idle
            case .starting: return .starting
            case .recording: return .recording
            case .transcribing: return .transcribing
            }
        }
    }

    /// Upper bound for one recording; both streams are held in memory until it ends.
    static let maxSeconds: Double = 2 * 60 * 60

    @Published private(set) var state: State = .idle
    @Published private(set) var lastError: String?

    private let transcriber: WhisperKitTranscriber
    private let dictionary: DictionaryStore
    private let system = SystemAudioRecorder()
    private let microphone = AudioRecorder()
    /// Ends the recording at `maxSeconds` by a monotonic clock. The microphone's own sample limit does
    /// the same, but the microphone is optional: with the Mac's sound alone nothing else would end it.
    private var limit: Task<Void, Never>?
    /// The capture stream reported its end while the start was still opening it: the start is aborted
    /// instead of recording on a dead stream.
    private var streamStoppedWhileStarting = false
    /// A `system.start()` that was given up on (timed out) has not returned yet. Until it has, no new
    /// recording may begin: the one shared recorder cannot be started twice, and the late teardown of
    /// the old start must never close a capture a newer recording owns.
    private var systemStartPending = false

    init(transcriber: WhisperKitTranscriber, dictionary: DictionaryStore) {
        self.transcriber = transcriber
        self.dictionary = dictionary
        microphone.maxSeconds = Self.maxSeconds
        microphone.onLimitReached = { [weak self] in self?.stop() }
        system.onStopped = { [weak self] in self?.systemStopped() }
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
        guard state.phase.acceptsStart else { return }
        guard RecordingStartDecision.mayStart(systemStartPending: systemStartPending) else {
            return fail("前回の開始処理がまだ終わっていません。少し待ってからお試しください")
        }
        guard transcriber.isReady else { return fail("モデルを準備中です") }
        lastError = nil
        // Held from here on: a second start or a file job asked for while the sources open is refused.
        state = .starting
        streamStoppedWhileStarting = false
        Task {
            let outcome = await openSystemAudio()
            switch RecordingStartDecision.decide(outcome: outcome, streamStoppedWhileStarting: streamStoppedWhileStarting) {
            case .abortNotPermitted:
                state = .idle
                return fail("Mac の音を取り込めませんでした。システム設定の「画面収録とシステムオーディオ録音」で KoeType を許可してください。")
            case .abortTimedOut:
                state = .idle
                return fail("Mac の音の取り込みが始まりませんでした。もう一度お試しください")
            case .abortStreamStopped:
                // Idle first, so a close that hangs cannot hold the starting phase; starts stay refused
                // through `systemStartPending` until the close has returned.
                state = .idle
                fail("Mac の音の取り込みが止まりました。もう一度お試しください")
                systemStartPending = true
                _ = await system.stop()
                systemStartPending = false
                return
            case .record:
                break
            }
            // The microphone is optional: a video can be transcribed without it, so a failure to open
            // it (reported through onInterrupted, which is not set here) is ignored.
            microphone.start()
            let since = Date()
            let began = ContinuousClock.now
            state = .recording(since: since)
            limit = Task { [weak self] in
                // Sleeps for what is left and checks again, so an early wake never skips the limit; the
                // clock is monotonic, so a wall clock set back cannot either.
                while !Task.isCancelled {
                    let elapsed = Self.seconds(since: began)
                    if RecordingLimit.reached(elapsedSeconds: elapsed, maxSeconds: Self.maxSeconds) { break }
                    let remaining = RecordingLimit.remainingSeconds(elapsedSeconds: elapsed, maxSeconds: Self.maxSeconds)
                    try? await Task.sleep(for: .seconds(remaining))
                }
                // Only the recording this timer was set for.
                guard let self, !Task.isCancelled, case .recording(let started) = self.state, started == since else { return }
                self.stop()
            }
        }
    }

    /// Opens the Mac's sound, for at most `RecordingStartDecision.timeoutSeconds`. ScreenCaptureKit can
    /// stay silent for good; then the start is given up and a success that comes later is torn down
    /// rather than used, so the session never sits in its starting phase forever.
    private func openSystemAudio() async -> RecordingStartDecision.Outcome {
        let claim = FirstClaim()
        let system = self.system
        systemStartPending = true
        return await withCheckedContinuation { continuation in
            Task {
                var outcome = RecordingStartDecision.Outcome.failed
                do {
                    try await system.start()
                    outcome = .started
                } catch {}
                if claim.take() {
                    // The start is the session's again: it decides what happens next.
                    systemStartPending = false
                    continuation.resume(returning: outcome)
                } else {
                    // Lost to the deadline: the session has moved on, so a capture that did come up is
                    // closed again. Starts stay refused until that close has fully returned, because
                    // `stop()` suspends the main actor while the capture stops and a start allowed in
                    // between would hand the recorder a new stream for the old stop to drop.
                    if outcome == .started { _ = await system.stop() }
                    systemStartPending = false
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + RecordingStartDecision.timeoutSeconds) {
                if claim.take() { continuation.resume(returning: .timedOut) }
            }
        }
    }

    /// The capture stream ended by itself. While recording that ends the recording; while still starting
    /// it is remembered, so the start is aborted as soon as it would otherwise begin recording.
    private func systemStopped() {
        if case .starting = state {
            streamStoppedWhileStarting = true
        } else {
            stop()
        }
    }

    func stop() {
        guard state.phase.acceptsStop, case .recording(let since) = state else { return }
        limit?.cancel()
        limit = nil
        state = .transcribing(progress: 0)
        Task {
            let played = await system.stop()
            let spoken = microphone.isRecording ? microphone.stop().samples : []
            // Mixing two hours of audio touches over a hundred million samples: never on the main actor,
            // which this session (and so this task) runs on.
            let mixed = await Task.detached { AudioMixer.mix(played, spoken) }.value
            await finish(samples: mixed, title: "記録", startedAt: since)
        }
    }

    /// Transcribes an existing sound or movie file.
    func transcribe(file url: URL) {
        guard state.phase.acceptsStart else { return }
        guard transcriber.isReady else { return fail("モデルを準備中です") }
        lastError = nil
        state = .transcribing(progress: 0)
        Task {
            let path = url.path
            guard let samples = await Task.detached(operation: { AudioFileLoader.load(path: path) }).value else {
                endTranscription()
                return fail("このファイルの音声を読み込めませんでした")
            }
            await finish(samples: samples, title: url.deletingPathExtension().lastPathComponent, startedAt: Date())
        }
    }

    /// `samples` are only handed on from here: the transcriber chunks and copies them off the main actor
    /// (it is not isolated to it), and what is left on main is the transcript text and a small file.
    private func finish(samples: [Float], title: String, startedAt: Date) async {
        defer { endTranscription() }
        guard !samples.isEmpty else { return fail("音声が記録されていませんでした") }
        do {
            let segments = try await transcriber.transcribeLong(
                samples: samples, hints: dictionary.hintText(maxCharacters: 120),
                progress: { value in Task { @MainActor [weak self] in self?.reportProgress(value) } })
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

    /// The transcription job is over: back to idle, but only while the session is still the job's.
    private func endTranscription() {
        if state.phase.endsWithTranscription { state = .idle }
    }

    private func reportProgress(_ value: Double) {
        if state.phase.endsWithTranscription { state = .transcribing(progress: value) }
    }

    private static func seconds(since began: ContinuousClock.Instant) -> Double {
        let elapsed = ContinuousClock.now - began
        return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    }

    private func fail(_ message: String) {
        lastError = message
        WindowManager.shared.showTranscript(text: message, file: nil)
    }
}
