import AppKit
import Combine
import KoeTypeCore

/// Owns the long-lived parts of the app and wires hotkey input to recording and the pipeline.
@MainActor
final class AppController: ObservableObject {
    static let shared = AppController()

    let settings = AppSettings.shared
    let dictionary: DictionaryStore
    let history: HistoryStore
    let transcriber: WhisperKitTranscriber
    let polisher: OpenAIPolisher
    let usage: UsageStore
    /// The polisher currently selected in settings (OpenAI API or Codex CLI).
    let activePolisher: Polishing
    @Published private(set) var hotkeyActive = false
    @Published private(set) var microphoneGranted = Permissions.microphoneGranted

    private let recorder = AudioRecorder()
    private let monitor = HotkeyMonitor()
    private let indicator = RecordingIndicator()
    private let copyBox: CopyBoxPanel
    private let pipeline: DictationPipeline
    private var machine = HotkeyStateMachine()
    /// Recordings handed to the pipeline that have not finished yet.
    private var pending = 0
    private var observers: Set<AnyCancellable> = []
    /// Shows the recording indicator or a refusal shortly after the key goes down.
    /// A plain shortcut (trigger + another key) cancels it before anything appears.
    private var delayedIndicator: Task<Void, Never>?
    private static let indicatorDelay: UInt64 = 200_000_000
    /// True once the recording indicator has been allowed on screen for the current recording.
    private var recordingShown = false
    private var message: String?
    private var messageTask: Task<Void, Never>?
    private var stage: IndicatorStage = .transcribing

    private init() {
        let dictionary = DictionaryStore(fileURL: AppPaths.dictionaryFile)
        let history = HistoryStore(fileURL: AppPaths.historyFile)
        let transcriber = WhisperKitTranscriber()
        let copyBox = CopyBoxPanel()
        let usage = UsageStore(fileURL: AppPaths.usageFile)
        let polisher = OpenAIPolisher(
            apiKey: { KeychainStore.readAPIKey() },
            model: { UserDefaults.standard.string(forKey: "polishModel") ?? AppSettings.defaultPolishModel },
            onUsage: { try? usage.record($0, at: Date()) })
        self.usage = usage
        let activePolisher = BackendPolisher(
            openAI: polisher,
            codex: CodexPolisher(
                executable: { AppSettings.codexPath },
                model: { UserDefaults.standard.string(forKey: "codexModel") ?? AppSettings.defaultCodexModel },
                runner: ProcessRunner()),
            usesCodex: { UserDefaults.standard.bool(forKey: "polishViaCodex") })
        self.activePolisher = activePolisher
        self.dictionary = dictionary
        self.history = history
        self.transcriber = transcriber
        self.copyBox = copyBox
        self.polisher = polisher
        pipeline = DictationPipeline(
            transcriber: transcriber, polisher: activePolisher, deliverer: TextInserter(copyBox: copyBox),
            dictionary: dictionary, history: history,
            polishEnabled: { UserDefaults.standard.object(forKey: "polishEnabled") as? Bool ?? false },
            minimumAICharacters: {
                UserDefaults.standard.object(forKey: "minimumAICharacters") as? Int
                    ?? AppSettings.defaultMinimumAICharacters
            },
            onStatus: { status in DispatchQueue.main.async { AppController.shared.handle(status) } })
    }

    /// One line for the menu describing what the app is doing or what it needs.
    var statusText: String {
        if !microphoneGranted { return "マイクの許可が必要です" }
        if !hotkeyActive { return "アクセシビリティの許可が必要です" }
        switch transcriber.state {
        case .notLoaded: return "モデルを準備中"
        case .downloading(let progress): return "モデルをダウンロード中 \(Int(progress * 100))%"
        case .loading: return "モデルを読み込み中"
        case .failed: return "モデルの読み込みに失敗しました"
        case .ready: return "待機中（\(settings.hotkey.label) を押しながら話す）"
        }
    }

    var isReady: Bool { microphoneGranted && hotkeyActive && transcriber.isReady }

    func start() {
        transcriber.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &observers)
        recorder.onLevel = { [weak self] level in self?.indicator.setLevel(level) }
        recorder.onLimitReached = { [weak self] in self?.endRecordingWithoutKey() }
        recorder.onInterrupted = { [weak self] in
            self?.endRecordingWithoutKey()
            self?.show(message: "マイクが切り替わったため、ここまでを入力します")
        }
        monitor.onInput = { [weak self] input, time in
            guard let self else { return }
            if input == .otherKeyDown || input == .triggerUp { self.delayedIndicator?.cancel() }
            for action in self.machine.handle(input, at: time) { self.perform(action) }
        }
        Task {
            _ = await Permissions.requestMicrophone()
            refreshPermissions()
        }
        reloadHotkey()
        reloadModel()
        if !Permissions.microphoneGranted || !Permissions.accessibilityGranted {
            WindowManager.shared.showOnboarding()
        }
    }

    func reloadHotkey() {
        hotkeyActive = monitor.start(choice: settings.hotkey)
    }

    func reloadModel() {
        let model = settings.whisperModel
        Task { await transcriber.load(model: model) }
    }

    func refreshPermissions() {
        microphoneGranted = Permissions.microphoneGranted
        if !hotkeyActive, Permissions.accessibilityGranted { reloadHotkey() }
    }

    private func perform(_ action: HotkeyStateMachine.Action) {
        switch action {
        case .startRecording:
            guard transcriber.isReady else { return refuse("モデルを準備中です") }
            guard Permissions.microphoneGranted else { return refuse("マイクの使用が許可されていません") }
            do {
                try recorder.start()
                recordingShown = false
                showDelayed { [weak self] in
                    guard let self, self.recorder.isRecording else { return }
                    self.recordingShown = true
                    self.refreshIndicator()
                }
            } catch {
                refuse("マイクを開始できませんでした")
            }
        case .enterHandsFree:
            delayedIndicator?.cancel()
            recordingShown = recorder.isRecording
            refreshIndicator()
        case .cancelRecording:
            delayedIndicator?.cancel()
            recorder.cancel()
            refreshIndicator()
        case .stopAndProcess:
            delayedIndicator?.cancel()
            submitRecording()
        }
    }

    /// The recorder stopped on its own (time limit or device change): keep what was said.
    private func endRecordingWithoutKey() {
        guard recorder.isRecording else { return }
        machine.recordingEndedByLimit(at: ProcessInfo.processInfo.systemUptime)
        delayedIndicator?.cancel()
        submitRecording()
    }

    private func submitRecording() {
        guard recorder.isRecording else { return }
        let (samples, seconds) = recorder.stop()
        if seconds >= 0.3 {
            pending += 1
            stage = .transcribing
            pipeline.submit(samples: samples, durationSeconds: seconds)
        }
        refreshIndicator()
    }

    private func refuse(_ text: String) {
        machine.reset()
        showDelayed { [weak self] in self?.show(message: text) }
    }

    private func showDelayed(_ show: @escaping @MainActor () -> Void) {
        delayedIndicator?.cancel()
        delayedIndicator = Task {
            try? await Task.sleep(nanoseconds: Self.indicatorDelay)
            guard !Task.isCancelled else { return }
            show()
        }
    }

    /// Keeps a message on screen for two seconds even while other recordings are being processed.
    private func show(message text: String) {
        message = text
        messageTask?.cancel()
        messageTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            self?.message = nil
            self?.refreshIndicator()
        }
        refreshIndicator()
    }

    private func refreshIndicator() {
        let recording: RecordingState
        if recorder.isRecording, recordingShown {
            recording = machine.isHandsFree ? .handsFree : .holding
        } else {
            recording = .none
        }
        indicator.set(IndicatorPolicy.display(recording: recording, message: message, pending: pending, stage: stage))
    }

    private func handle(_ status: PipelineStatus) {
        switch status {
        case .transcribing:
            stage = .transcribing
        case .polishing:
            stage = .polishing
        case .delivered:
            pending = max(0, pending - 1)
        case .nothingHeard:
            pending = max(0, pending - 1)
            show(message: "聞き取れませんでした")
        case .failed(let text):
            pending = max(0, pending - 1)
            show(message: text)
        case .warning(let text):
            show(message: text)
        }
        refreshIndicator()
    }
}
