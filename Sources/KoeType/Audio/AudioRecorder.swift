import AVFoundation

enum AudioRecorderError: Error { case noInputDevice, engineFailed(Error) }

final class AudioRecorder {
    static let sampleRate: Double = 16_000
    static let maxSeconds: Double = 600

    var onLevel: ((Float) -> Void)?
    var onLimitReached: (() -> Void)?
    private(set) var isRecording = false

    private var engine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private let lock = NSLock()
    private var samples: [Float] = []
    private var limitFired = false

    func start() throws {
        cancel()
        // A fresh engine per recording picks up device changes (AirPods connect, mic unplugged).
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw AudioRecorderError.noInputDevice
        }
        let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Self.sampleRate,
                                   channels: 1, interleaved: false)!
        guard let converter = AVAudioConverter(from: inputFormat, to: target) else {
            throw AudioRecorderError.noInputDevice
        }
        lock.withLock { samples.removeAll(keepingCapacity: true) }
        limitFired = false
        input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            self?.append(buffer, converter: converter, target: target)
        }
        do {
            engine.prepare()
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw AudioRecorderError.engineFailed(error)
        }
        self.engine = engine
        self.converter = converter
        isRecording = true
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
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        converter = nil
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
            self.onLevel?(min(1, rms * 8))
            if !self.limitFired, Double(total) / Self.sampleRate >= Self.maxSeconds {
                self.limitFired = true
                self.onLimitReached?()
            }
        }
    }
}
