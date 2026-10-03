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

    private init() {
        let dictionary = DictionaryStore(fileURL: AppPaths.dictionaryFile)
        let history = HistoryStore(fileURL: AppPaths.historyFile)
        let transcriber = WhisperKitTranscriber()
        let copyBox = CopyBoxPanel()
        let polisher = OpenAIPolisher(
            apiKey: { KeychainStore.readAPIKey() },
            model: { UserDefaults.standard.string(forKey: "polishModel") ?? AppSettings.defaultPolishModel })
        self.dictionary = dictionary
        self.history = history
        self.transcriber = transcriber
        self.copyBox = copyBox
        self.polisher = polisher
        pipeline = DictationPipeline(
            transcriber: transcriber, polisher: polisher, deliverer: TextInserter(copyBox: copyBox),
            dictionary: dictionary, history: history,
            polishEnabled: { UserDefaults.standard.object(forKey: "polishEnabled") as? Bool ?? true },
            onStatus: { status in Task { @MainActor in AppController.shared.handle(status) } })
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

    var isReady: Bool { microphoneGranted && hotkeyActive && transcriber.state == .ready }

    func start() {
        transcriber.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &observers)
        recorder.onLevel = { [weak self] level in self?.indicator.setLevel(level) }
        recorder.onLimitReached = { [weak self] in
            guard let self else { return }
            self.machine.reset()
            self.perform(.stopAndProcess)
        }
        monitor.onInput = { [weak self] input, time in
            guard let self else { return }
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
            guard transcriber.state == .ready else { return refuse("モデルを準備中です") }
            guard Permissions.microphoneGranted else { return refuse("マイクの使用が許可されていません") }
            do {
                try recorder.start()
                indicator.set(.recording(handsFree: false))
            } catch {
                refuse("マイクを開始できませんでした")
            }
        case .enterHandsFree:
            if recorder.isRecording { indicator.set(.recording(handsFree: true)) }
        case .cancelRecording:
            recorder.cancel()
            showIdleOrProcessing()
        case .stopAndProcess:
            guard recorder.isRecording else { return }
            let (samples, seconds) = recorder.stop()
            guard seconds >= 0.3 else { return showIdleOrProcessing() }
            pending += 1
            indicator.set(.processing)
            pipeline.submit(samples: samples, durationSeconds: seconds)
        }
    }

    private func refuse(_ message: String) {
        machine.reset()
        indicator.set(.message(message))
    }

    private func showIdleOrProcessing() {
        indicator.set(pending == 0 ? .hidden : .processing)
    }

    private func handle(_ status: PipelineStatus) {
        switch status {
        case .transcribing, .polishing:
            if !recorder.isRecording { indicator.set(.processing) }
        case .delivered:
            pending = max(0, pending - 1)
            if !recorder.isRecording { showIdleOrProcessing() }
        case .nothingHeard:
            pending = max(0, pending - 1)
            if !recorder.isRecording { indicator.set(.message("聞き取れませんでした")) }
        case .failed(let message):
            pending = max(0, pending - 1)
            if !recorder.isRecording { indicator.set(.message(message)) }
        }
    }
}
