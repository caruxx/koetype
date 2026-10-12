import AVFoundation
import AudioToolbox
import CoreAudio
import KoeTypeCore

enum AudioRecorderError: Error { case noInputDevice, engineFailed(Error) }

final class AudioRecorder {
    static let sampleRate: Double = 16_000
    /// Recording stops by itself after this long. Dictation uses the default; long recordings raise it.
    var maxSeconds: Double = 600

    var onLevel: ((Float) -> Void)?
    var onLimitReached: (() -> Void)?
    /// Which microphone to use; read at every `start()` so a change in settings applies at once.
    var preference: () -> MicrophonePreference = { .systemDefault }
    /// The input device disappeared while recording and the engine could not be restarted. Called on the main queue.
    var onInterrupted: (() -> Void)?
    private var configurationObserver: NSObjectProtocol?
    private(set) var isRecording = false

    private var engine: AVAudioEngine?
    /// How many times one recording may restart the engine after a configuration change.
    private static let maxRestarts = 3
    private var restarts = 0
    private let lock = NSLock()
    private var samples: [Float] = []
    private var limitFired = false

    func start() throws {
        cancel()
        lock.withLock { samples.removeAll(keepingCapacity: true) }
        limitFired = false
        restarts = 0
        // A fresh engine per recording picks up device changes (AirPods connect, mic unplugged).
        let engine = AVAudioEngine()
        // Point the engine at the chosen microphone before asking for its format.
        if var deviceID = AudioDevices.deviceID(for: preference()), let unit = engine.inputNode.audioUnit {
            AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                 &deviceID, UInt32(MemoryLayout<AudioDeviceID>.size))
        }
        try run(engine)
        self.engine = engine
        isRecording = true
        // A Bluetooth headset switches to its call profile once its microphone opens, which stops the
        // engine shortly after it starts. Start it again with the new format and keep what was captured.
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            guard let self, self.isRecording, let engine = self.engine else { return }
            if self.restarts < Self.maxRestarts, (try? self.run(engine)) != nil {
                self.restarts += 1
            } else {
                self.onInterrupted?()
            }
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

    func stop() -> (samples: [Float], durationSeconds: Double) {
        teardown()
        let result = lock.withLock { samples }
        return (result, Double(result.count) / Self.sampleRate)
    }

    func cancel() {
        teardown()
        lock.withLock { samples.removeAll() }
    }

    private func teardown() {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        isRecording = false
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
        let total: Int = lock.withLock { samples.append(contentsOf: chunk); return samples.count }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onLevel?(LevelMeter.display(rms: rms))
            if !self.limitFired, Double(total) / Self.sampleRate >= self.maxSeconds {
                self.limitFired = true
                self.onLimitReached?()
            }
        }
    }
}
