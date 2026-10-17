import AVFoundation
import AudioToolbox
import CoreAudio
import KoeTypeCore

enum AudioRecorderError: Error { case noInputDevice, engineFailed(Error) }

/// Why a recording ended without the user stopping it.
enum AudioInterruption {
    case microphoneSwitched, microphoneStopped
    /// The microphone could not be opened: nothing was captured.
    case microphoneUnavailable
    /// Core Audio did not answer within `EngineStartPolicy.timeout`: nothing was captured.
    case microphoneUnresponsive
}

/// Records 16 kHz mono audio from the chosen microphone.
///
/// `start()`, `stop()` and `cancel` are called from the main queue and never block: every call into
/// AVAudioEngine and the Core Audio HAL runs on one serial queue owned by a `Worker`, because those
/// calls can stall for seconds or for good (a Bluetooth headset switching profiles, Continuity
/// microphones). A start that does not report back in time is given up on from the main queue: its
/// worker is replaced and the stuck engine is never used again, whenever it does come back.
final class AudioRecorder {
    static let sampleRate: Double = 16_000
    /// Recording stops by itself after this long. Dictation uses the default; long recordings raise it.
    var maxSeconds: Double = 600

    var onLevel: ((Float) -> Void)?
    var onLimitReached: (() -> Void)?
    /// Which microphone to use; read at every `start()` so a change in settings applies at once.
    var preference: () -> MicrophonePreference = { .systemDefault }
    /// The microphone went away, input moved to another device, the engine could not be started
    /// (again), or it did not respond. Called on the main queue; `stop()` still returns what was captured.
    var onInterrupted: ((AudioInterruption) -> Void)?
    var isRecording: Bool { lock.withLock { recording } }

    private let lock = NSLock()
    private var recording = false   // guarded by `lock`
    private var samples: [Float] = []   // guarded by `lock`
    private var capturing = false   // guarded by `lock`
    /// Audio from before this host time was captured before the key went down.
    private var captureFrom: UInt64 = 0   // guarded by `lock`
    /// Counts recordings, so changes and retries left over from an earlier one can be told apart.
    private var generation = 0   // guarded by `lock`
    /// The newest recording whose engine start has reported back, so a stalled start can be told.
    private var lastCompletedStart = 0   // guarded by `lock`
    private var limitFired = false   // main queue only
    /// Owns the engine and its queue. Replaced from the main queue when a start stalls.
    private var worker: Worker

    init() {
        worker = Worker()
        worker.recorder = self
    }

    deinit {
        let worker = self.worker
        worker.queue.async { worker.discardEngine() }
    }

    /// Begins a recording at once: audio the engine delivers from now on is kept, and the engine is
    /// opened or reused on the worker's queue. Failures arrive through `onInterrupted`.
    func start() {
        let now = mach_absolute_time()
        let started: Int = lock.withLock {
            samples.removeAll(keepingCapacity: true)
            capturing = true
            captureFrom = now
            generation += 1
            recording = true
            return generation
        }
        limitFired = false
        let wanted = preference()
        let worker = self.worker
        worker.queue.async { worker.start(wanted: wanted, generation: started) }
        DispatchQueue.main.asyncAfter(deadline: .now() + EngineStartPolicy.timeout) { [weak self] in
            self?.giveUpIfStillWaiting(for: started, on: worker)
        }
    }

    func stop() -> (samples: [Float], durationSeconds: Double) {
        endCapture()
        let worker = self.worker
        worker.queue.async { worker.stopEngine() }
        let result = lock.withLock { samples }
        return (result, Double(result.count) / Self.sampleRate)
    }

    func cancel() {
        endCapture()
        let worker = self.worker
        worker.queue.async { worker.stopEngine() }
        lock.withLock { samples.removeAll() }
    }

    /// Discards the recording but leaves the microphone open for a moment, so a second tap starts
    /// hands-free at once instead of opening it again (a Bluetooth headset takes about a second).
    /// Nothing is kept while it is open.
    func cancel(keepingMicrophoneOpenFor seconds: TimeInterval) {
        guard isRecording else { return cancel() }
        endCapture()
        lock.withLock { samples.removeAll() }
        let worker = self.worker
        worker.queue.async { worker.keepOpen(for: seconds) }
    }

    private func endCapture() {
        lock.withLock {
            capturing = false
            recording = false
        }
    }

    /// The start made for `started` has not reported back: the microphone is not responding. The
    /// worker is left to its stalled call and replaced, so the next recording gets a fresh engine.
    private func giveUpIfStillWaiting(for started: Int, on worker: Worker) {
        let giveUp: Bool = lock.withLock {
            guard EngineStartPolicy.givesUp(started: started, current: generation, lastCompleted: lastCompletedStart) else {
                return false
            }
            lastCompletedStart = started
            capturing = false
            recording = false
            return true
        }
        guard giveUp, worker === self.worker else { return }
        worker.abandon()
        self.worker = Worker()
        self.worker.recorder = self
        onInterrupted?(.microphoneUnresponsive)
    }

    // MARK: Called by the worker (on its queue)

    fileprivate var currentGeneration: Int { lock.withLock { generation } }

    /// The engine for recording `started` is running (or was still open). Returns false when the
    /// recorder has moved on and the engine must not be used.
    fileprivate func engineStarted(for started: Int, abandoned: Bool) -> Bool {
        lock.withLock {
            lastCompletedStart = max(lastCompletedStart, started)
            return EngineStartPolicy.acceptsEngine(abandoned: abandoned, started: started, current: generation)
        }
    }

    fileprivate func startFailed(for started: Int) {
        let current: Bool = lock.withLock {
            lastCompletedStart = max(lastCompletedStart, started)
            guard started == generation else { return false }
            capturing = false
            recording = false
            return true
        }
        guard current else { return }
        DispatchQueue.main.async { [weak self] in self?.onInterrupted?(.microphoneUnavailable) }
    }

    fileprivate func interrupted(_ reason: AudioInterruption, generation posted: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.lock.withLock({ self.recording && self.generation == posted }) else { return }
            self.onInterrupted?(reason)
        }
    }

    fileprivate func append(_ buffer: AVAudioPCMBuffer, at when: AVAudioTime, converter: AVAudioConverter, target: AVAudioFormat) {
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
        var consumed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if consumed { status.pointee = .noDataNow; return nil }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let channel = out.floatChannelData?[0], out.frameLength > 0 else { return }
        let chunk = Array(UnsafeBufferPointer(start: channel, count: Int(out.frameLength)))
        let rms = sqrt(chunk.reduce(0) { $0 + $1 * $1 } / Float(chunk.count))
        // While the microphone is only being kept open, nothing is recorded or shown, and a buffer that
        // began before the key went down is left out too.
        let total: Int? = lock.withLock {
            guard capturing, !when.isHostTimeValid || when.hostTime >= captureFrom else { return nil }
            samples.append(contentsOf: chunk)
            return samples.count
        }
        guard let total else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isRecording else { return }
            self.onLevel?(LevelMeter.display(rms: rms))
            if !self.limitFired, Double(total) / Self.sampleRate >= self.maxSeconds {
                self.limitFired = true
                self.onLimitReached?()
            }
        }
    }
}

/// Everything that touches AVAudioEngine and Core Audio. All of it runs on `queue`; the recorder only
/// ever enqueues work and reads its own lock-guarded state. One worker is used for as long as its
/// calls return; a worker whose start stalls is abandoned together with its engine.
private final class Worker {
    let queue = DispatchQueue(label: "jp.caruvistar.koetype.audio-engine")
    weak var recorder: AudioRecorder?

    /// Kept for a short while between recordings: creating an engine's input node takes about 0.2 s.
    /// It is not kept for good, because while it exists a Bluetooth headset stays in its call profile
    /// and everything it plays sounds worse.
    private var engine: AVAudioEngine?
    private static let keepEngineSeconds: TimeInterval = 10
    private var releaseLater: DispatchWorkItem?
    private var configurationObserver: NSObjectProtocol?
    private var activePreference: MicrophonePreference = .systemDefault
    /// The microphone the kept engine was made for. A kept engine never follows a change by itself.
    private var engineMicrophone: String?
    /// Set when a recording ended because the microphone switched or stopped: that engine is not kept.
    private var discardOnStop = false
    /// The microphone this recording started on, to tell a real switch from a Bluetooth profile change.
    private var startedOn: String?
    /// Set while the microphone stays open after a short tap (see `keepOpen(for:)`).
    private var closeLater: DispatchWorkItem?
    /// Guards against an endless restart loop within one recording.
    private static let maxRestarts = 10
    private var restarts = 0
    private let lock = NSLock()
    /// The recorder gave up waiting for this worker. Read on the queue and in the tap; set from main.
    private var abandoned = false   // guarded by `lock`

    var isAbandoned: Bool { lock.withLock { abandoned } }

    /// Called from the main queue. The engine is closed whenever the stalled call lets go of the queue.
    func abandon() {
        lock.withLock { abandoned = true }
        queue.async { [self] in discardEngine() }
    }

    func start(wanted: MicrophonePreference, generation: Int) {
        guard let recorder else { return }
        releaseLater?.cancel()
        releaseLater = nil
        let stillOpen = closeLater != nil && engine?.isRunning == true
        closeLater?.cancel()
        closeLater = nil
        restarts = 0
        // The microphone is already delivering audio: recording starts at once.
        if stillOpen {
            if !recorder.engineStarted(for: generation, abandoned: isAbandoned) { discardEngine() }
            return
        }
        // The engine is pointed at its microphone once, when it is made. If another microphone is to be
        // used now (a new choice, the chosen one connected, or a new system default), make a new one.
        if discardOnStop || wanted != activePreference || AudioDevices.inputUID(for: wanted) != engineMicrophone {
            discardEngine()
        }
        activePreference = wanted
        do {
            try run(reusableEngine())
        } catch {
            // A kept engine can be left unusable by device changes while idle; try once with a new one.
            discardEngine()
            do {
                try run(reusableEngine())
            } catch {
                discardEngine()
                recorder.startFailed(for: generation)
                return
            }
        }
        startedOn = engineMicrophone
        // The recorder may have given up while Core Audio was busy: then this engine is closed, not used.
        if !recorder.engineStarted(for: generation, abandoned: isAbandoned) { discardEngine() }
    }

    func keepOpen(for seconds: TimeInterval) {
        guard engine?.isRunning == true else { return stopEngine() }
        closeLater?.cancel()
        let close = DispatchWorkItem { [weak self] in self?.stopEngine() }
        closeLater = close
        queue.asyncAfter(deadline: .now() + seconds, execute: close)
    }

    func stopEngine() {
        closeLater?.cancel()
        closeLater = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        guard engine != nil else { return }
        if discardOnStop { return discardEngine() }
        releaseLater?.cancel()
        let release = DispatchWorkItem { [weak self] in
            guard let self, self.recorder?.isRecording != true, self.closeLater == nil else { return }
            self.discardEngine()
        }
        releaseLater = release
        queue.asyncAfter(deadline: .now() + Self.keepEngineSeconds, execute: release)
    }

    func discardEngine() {
        releaseLater?.cancel()
        releaseLater = nil
        closeLater?.cancel()
        closeLater = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        engine = nil
        engineMicrophone = nil
        discardOnStop = false
    }

    private func reusableEngine() -> AVAudioEngine {
        if let engine { return engine }
        let engine = AVAudioEngine()
        // Pointing the engine at a microphone is itself a configuration change, so it is done only here.
        // Without a choice the engine follows the system default by itself.
        if var deviceID = AudioDevices.deviceID(for: activePreference), let unit = engine.inputNode.audioUnit {
            AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                 &deviceID, UInt32(MemoryLayout<AudioDeviceID>.size))
        }
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self, weak engine] _ in
            guard let self, let posted = self.recorder?.currentGeneration else { return }
            // Deferred so the handler never runs inside the engine call that posted the change.
            self.queue.async { [weak self] in
                guard let self, let engine else { return }
                self.configurationChanged(engine, posted: posted)
            }
        }
        self.engine = engine
        engineMicrophone = AudioDevices.inputUID(for: activePreference)
        return engine
    }

    /// A Bluetooth headset switches to its call profile once its microphone opens, which stops the
    /// engine shortly after it starts. That is the same microphone: start again and keep what was
    /// captured. Only a real switch to another microphone ends the recording.
    private func configurationChanged(_ changed: AVAudioEngine, posted: Int) {
        guard let recorder, !isAbandoned, changed === engine, recorder.isRecording || closeLater != nil else { return }
        // A change from before the current recording matters only if it left the engine stopped.
        if posted != recorder.currentGeneration, changed.isRunning { return }
        let change = MicrophoneChange.classify(startedOn: startedOn, now: AudioDevices.inputUID(for: activePreference))
        guard change == .sameMicrophone else { return interrupt(.microphoneSwitched) }
        guard restarts < Self.maxRestarts else { return interrupt(.microphoneStopped) }
        restarts += 1
        restart(changed, generation: recorder.currentGeneration, attemptsLeft: 4, wait: 0.15)
    }

    private func restart(_ engine: AVAudioEngine, generation: Int, attemptsLeft: Int, wait: TimeInterval) {
        // A retry left over from an earlier recording must not touch this one.
        guard let recorder, !isAbandoned, engine === self.engine, generation == recorder.currentGeneration,
              recorder.isRecording || closeLater != nil else { return }
        do {
            try run(engine)
        } catch {
            guard attemptsLeft > 1 else { return interrupt(.microphoneStopped) }
            // The headset may still be settling into its new profile (about a second): wait longer each time.
            queue.asyncAfter(deadline: .now() + wait) { [weak self] in
                self?.restart(engine, generation: generation, attemptsLeft: attemptsLeft - 1, wait: wait * 2)
            }
        }
    }

    private func interrupt(_ reason: AudioInterruption) {
        discardOnStop = true
        guard let recorder, recorder.isRecording else { return discardEngine() }
        recorder.interrupted(reason, generation: recorder.currentGeneration)
    }

    /// (Re)attaches the tap with the input's current format and starts the engine.
    private func run(_ engine: AVAudioEngine) throws {
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        engine.stop()
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw AudioRecorderError.noInputDevice
        }
        let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: AudioRecorder.sampleRate,
                                   channels: 1, interleaved: false)!
        // The format is passed as nil so the tap always matches the hardware: a stale format raises an
        // Objective-C exception that ends the app. The converter follows whatever the buffers carry.
        var converter: AVAudioConverter?
        input.installTap(onBus: 0, bufferSize: 2048, format: nil) { [weak self] buffer, when in
            // An abandoned worker's engine may come alive late: its audio never reaches the recorder.
            guard let self, !self.isAbandoned, let recorder = self.recorder else { return }
            if converter?.inputFormat != buffer.format {
                converter = AVAudioConverter(from: buffer.format, to: target)
            }
            guard let converter else { return }
            recorder.append(buffer, at: when, converter: converter, target: target)
        }
        do {
            engine.prepare()
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw AudioRecorderError.engineFailed(error)
        }
    }
}
