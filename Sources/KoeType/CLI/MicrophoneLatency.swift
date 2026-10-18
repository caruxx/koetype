import AVFoundation
import Foundation
import KoeTypeCore

/// Verification aid: measures how long the microphone takes to deliver audio after `start()`.
/// Runs on the main actor like the app, since `AudioRecorder` is driven from the main queue. `start()`
/// itself returns at once; the engine comes up on the recorder's own queue, so "first audio after" is
/// the figure that matters. A microphone that fails or does not respond is printed as an interruption.
@MainActor
enum MicrophoneLatency {
    static func run() async -> Int32 {
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            print("microphone access not granted to this process")
            return 2
        }
        let recorder = AudioRecorder()
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--mic"), index + 1 < arguments.count {
            let preference = MicrophonePreference(stored: arguments[index + 1])
            recorder.preference = { preference }
        }
        for entry in AudioDevices.inputs() {
            print("input device: \(entry.device.name) builtIn=\(entry.device.isBuiltIn)")
        }
        // With --double-tap each attempt is a short tap followed by a second press, as when starting hands-free.
        let doubleTap = arguments.contains("--double-tap")
        recorder.onInterrupted = { reason in print("interrupted: \(reason)") }
        for attempt in 1...4 {
            let began = Date()
            var firstBuffer: Date?
            recorder.onLevel = { _ in if firstBuffer == nil { firstBuffer = Date() } }
            if doubleTap {
                recorder.start()
                try? await Task.sleep(nanoseconds: 150_000_000)
                recorder.cancel(keepingMicrophoneOpenFor: 0.6)
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
            recorder.start()
            let started = Date()
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            let result = recorder.stop()
            let captured = result.durationSeconds
            let peak = result.samples.map { abs($0) }.max() ?? 0
            print(String(format: "attempt %d: start() %.0f ms, first audio after %.0f ms, captured %.2f s of 1.50 s, peak level %.4f",
                         attempt, started.timeIntervalSince(began) * 1000,
                         (firstBuffer ?? Date()).timeIntervalSince(began) * 1000, captured, peak))
            try? await Task.sleep(nanoseconds: 700_000_000)
        }
        return 0
    }
}
