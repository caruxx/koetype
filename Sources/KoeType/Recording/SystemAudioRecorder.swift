import AVFoundation
import ScreenCaptureKit

enum SystemAudioError: Error { case noDisplay, notPermitted }

/// Captures the sound the Mac is playing (meeting apps, browser video) as 16 kHz mono samples.
/// Uses ScreenCaptureKit, so macOS asks for the screen and system audio recording permission.
final class SystemAudioRecorder: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private let queue = DispatchQueue(label: "jp.caruvistar.koetype.system-audio")
    private let lock = NSLock()
    private var samples: [Float] = []
    /// Called on the main queue when capture stops unexpectedly.
    var onStopped: (() -> Void)?

    func start() async throws {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw SystemAudioError.notPermitted
        }
        guard let display = content.displays.first else { throw SystemAudioError.noDisplay }
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 16_000
        configuration.channelCount = 1
        // Video is not wanted; keep the mandatory video stream as small and slow as possible.
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        lock.withLock { samples.removeAll() }
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() async -> [Float] {
        try? await stream?.stopCapture()
        stream = nil
        return lock.withLock { samples }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid else { return }
        try? sampleBuffer.withAudioBufferList { list, _ in
            guard let buffer = list.first, let data = buffer.mData else { return }
            let count = Int(buffer.mDataByteSize) / MemoryLayout<Float32>.size
            let pointer = data.bindMemory(to: Float32.self, capacity: count)
            let chunk = Array(UnsafeBufferPointer(start: pointer, count: count))
            lock.withLock { samples.append(contentsOf: chunk) }
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in self?.onStopped?() }
    }
}
