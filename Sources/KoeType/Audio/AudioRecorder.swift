import AVFoundation
import AudioToolbox
import CoreAudio
import KoeTypeCore

enum AudioRecorderError: Error { case noInputDevice, engineFailed(Error) }

/// Why a recording ended without the user stopping it.
enum AudioInterruption { case microphoneSwitched, microphoneStopped }

final class AudioRecorder {
    static let sampleRate: Double = 16_000
    /// Recording stops by itself after this long. Dictation uses the default; long recordings raise it.
    var maxSeconds: Double = 600

    var onLevel: ((Float) -> Void)?
    var onLimitReached: (() -> Void)?
    /// Which microphone to use; read at every `start()` so a change in settings applies at once.
    var preference: () -> MicrophonePreference = { .systemDefault }
    /// The microphone went away, input moved to another device, or the engine could not be started
    /// again. Called on the main queue; `stop()` still returns what was captured.
    var onInterrupted: ((AudioInterruption) -> Void)?
    private(set) var isRecording = false

    /// Kept for a short while between recordings: creating an engine's input node takes about 0.2 s.
    /// It is not kept for good, because while it exists a Bluetooth headset stays in its call profile
    /// and everything it plays sounds worse.
    private var engine: AVAudioEngine?
    private static let keepEngineSeconds: TimeInterval = 10
    private var releaseLater: DispatchWorkItem?
    private var configurationObserver: NSObjectProtocol?
    private var activePreference: MicrophonePreference = .systemDefault
    /// The microphone this recording started on, to tell a real switch from a Bluetooth profile change.
    private var startedOn: String?
    /// Set while the microphone stays open after a short tap (see `cancel(keepingMicrophoneOpenFor:)`).
    private var closeLater: DispatchWorkItem?
    /// Guards against an endless restart loop within one recording.
    private static let maxRestarts = 10
    private var restarts = 0
    private let lock = NSLock()
    private var samples: [Float] = []
    private var capturing = false   // guarded by `lock`
    private var limitFired = false

    func start() throws {
        releaseLater?.cancel()
        releaseLater = nil
        let stillOpen = closeLater != nil && engine?.isRunning == true
        closeLater?.cancel()
        closeLater = nil
        lock.withLock {
            samples.removeAll(keepingCapacity: true)
            capturing = true
        }
        limitFired = false
        restarts = 0
        isRecording = true
        // The microphone is already delivering audio: recording starts at once.
        if stillOpen { return }
        let wanted = preference()
        // The engine is pointed at its microphone once, when it is made; a new choice needs a new engine.
        if wanted != activePreference { discardEngine() }
        activePreference = wanted
        startedOn = AudioDevices.inputUID(for: activePreference)
        do {
            try run(reusableEngine())
        } catch {
            // A kept engine can be left unusable by device changes while idle; try once with a new one.
            discardEngine()
            do {
                try run(reusableEngine())
            } catch {
                endCapture()
                discardEngine()
                throw error
            }
        }
    }

    func stop() -> (samples: [Float], durationSeconds: Double) {
        endCapture()
        stopEngine()
        let result = lock.withLock { samples }
        return (result, Double(result.count) / Self.sampleRate)
    }

    func cancel() {
        endCapture()
        stopEngine()
        lock.withLock { samples.removeAll() }
    }

    /// Discards the recording but leaves the microphone open for a moment, so a second tap starts
    /// hands-free at once instead of opening it again (a Bluetooth headset takes about a second).
    /// Nothing is kept while it is open.
    func cancel(keepingMicrophoneOpenFor seconds: TimeInterval) {
        guard isRecording, engine?.isRunning == true else { return cancel() }
        endCapture()
        lock.withLock { samples.removeAll() }
        let close = DispatchWorkItem { [weak self] in self?.stopEngine() }
        closeLater = close
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: close)
    }

    private func endCapture() {
        lock.withLock { capturing = false }
        isRecording = false
    }

    private func stopEngine() {
        closeLater?.cancel()
        closeLater = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        guard engine != nil else { return }
        releaseLater?.cancel()
        let release = DispatchWorkItem { [weak self] in
            guard let self, !self.isRecording, self.closeLater == nil else { return }
            self.discardEngine()
        }
        releaseLater = release
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.keepEngineSeconds, execute: release)
    }

    private func discardEngine() {
        releaseLater?.cancel()
        releaseLater = nil
        closeLater?.cancel()
        closeLater = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        engine = nil
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
            // Deferred so the handler never runs inside the engine call that posted the change.
            DispatchQueue.main.async {
                guard let self, let engine else { return }
                self.configurationChanged(engine)
            }
        }
        self.engine = engine
        return engine
    }

    /// A Bluetooth headset switches to its call profile once its microphone opens, which stops the
    /// engine shortly after it starts. That is the same microphone: start again and keep what was
    /// captured. Only a real switch to another microphone ends the recording.
    private func configurationChanged(_ changed: AVAudioEngine) {
        guard changed === engine, isRecording || closeLater != nil else { return }
        let change = MicrophoneChange.classify(startedOn: startedOn, now: AudioDevices.inputUID(for: activePreference))
        guard change == .sameMicrophone else { return interrupt(.microphoneSwitched) }
        guard restarts < Self.maxRestarts else { return interrupt(.microphoneStopped) }
        restarts += 1
        restart(changed, attemptsLeft: 3)
    }

    private func restart(_ engine: AVAudioEngine, attemptsLeft: Int) {
        guard engine === self.engine, isRecording || closeLater != nil else { return }
        do {
            try run(engine)
        } catch {
            guard attemptsLeft > 1 else { return interrupt(.microphoneStopped) }
            // The device may still be settling into its new profile.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.restart(engine, attemptsLeft: attemptsLeft - 1)
            }
        }
    }

    private func interrupt(_ reason: AudioInterruption) {
        if isRecording {
            onInterrupted?(reason)
        } else {
            stopEngine()
        }
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
        let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Self.sampleRate,
                                   channels: 1, interleaved: false)!
        // The format is passed as nil so the tap always matches the hardware: a stale format raises an
        // Objective-C exception that ends the app. The converter follows whatever the buffers carry.
        var converter: AVAudioConverter?
        input.installTap(onBus: 0, bufferSize: 2048, format: nil) { [weak self] buffer, _ in
            if converter?.inputFormat != buffer.format {
                converter = AVAudioConverter(from: buffer.format, to: target)
            }
            guard let converter else { return }
            self?.append(buffer, converter: converter, target: target)
        }
        do {
            engine.prepare()
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw AudioRecorderError.engineFailed(error)
        }
    }

    private func append(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter, target: AVAudioFormat) {
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
        // While the microphone is only being kept open, nothing is recorded or shown.
        let total: Int? = lock.withLock {
            guard capturing else { return nil }
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
