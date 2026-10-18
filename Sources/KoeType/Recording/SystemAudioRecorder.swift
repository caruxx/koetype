import AVFoundation
import ScreenCaptureKit

enum SystemAudioError: Error { case noDisplay, notPermitted }

/// Captures the sound the Mac is playing (meeting apps, browser video) as 16 kHz mono samples.
/// Uses ScreenCaptureKit, so macOS asks for the screen and system audio recording permission.
/// `start` and `stop` run on the thread pool, the output callbacks on their own queue, and the stop
/// notification on main: everything they share is guarded by one lock, never held across an await.
final class SystemAudioRecorder: NSObject, SCStreamOutput, SCStreamDelegate {
    private let queue = DispatchQueue(label: "jp.caruvistar.koetype.system-audio")
    private let lock = NSLock()
    /// The stream in use, registered before it is started so a stop reported during the start is not
    /// mistaken for an old stream's.
    private var stream: SCStream?   // guarded by `lock`
    private var samples: [Float] = []   // guarded by `lock`
    /// Buffers are kept only between a start and the first stop (or a stop that was given up on): a
    /// capture whose stop never returns must not go on filling memory after the recording was saved.
    private var accepting = false   // guarded by `lock`
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
        lock.withLock {
            samples.removeAll()
            accepting = true
            self.stream = stream
        }
        do {
            try await stream.startCapture()
        } catch {
            // Let go of it only if nothing newer has taken its place meanwhile.
            lock.withLock {
                if self.stream === stream {
                    self.stream = nil
                    accepting = false
                }
            }
            throw error
        }
    }

    /// Stops the capture. No more buffers are kept from the moment this is called, even if the stop
    /// itself takes long or never returns; the samples are handed over by `takeCapturedSamples()`.
    func stop() async {
        // Only the stream this call stopped is let go: a stream started while the stop was in flight
        // belongs to a newer recording and keeps its stop control.
        let stopping: SCStream? = lock.withLock {
            accepting = false
            return stream
        }
        try? await stopping?.stopCapture()
        lock.withLock { if stream === stopping { stream = nil } }
    }

    /// Hands over what was captured and frees it. Also ends the keeping of buffers, for a stop that
    /// did not return in time; a fresh `start()` keeps buffers again.
    func takeCapturedSamples() -> [Float] {
        lock.withLock {
            accepting = false
            defer { samples.removeAll() }
            return samples
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid else { return }
        try? sampleBuffer.withAudioBufferList { list, _ in
            guard let buffer = list.first, let data = buffer.mData else { return }
            let count = Int(buffer.mDataByteSize) / MemoryLayout<Float32>.size
            let pointer = data.bindMemory(to: Float32.self, capacity: count)
            let chunk = Array(UnsafeBufferPointer(start: pointer, count: count))
            lock.withLock {
                guard accepting else { return }
                samples.append(contentsOf: chunk)
            }
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            // An old stream reporting its end after a newer one took over says nothing about that one.
            guard let self, self.lock.withLock({ self.stream === stream }) else { return }
            self.onStopped?()
        }
    }
}
