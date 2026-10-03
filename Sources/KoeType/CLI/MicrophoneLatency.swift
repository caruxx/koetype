import AVFoundation
import Foundation

/// Verification aid: measures how long the microphone takes to deliver audio after `start()`.
enum MicrophoneLatency {
    static func run() async -> Int32 {
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            print("microphone access not granted to this process")
            return 2
        }
        let recorder = AudioRecorder()
        for attempt in 1...4 {
            let began = Date()
            var firstBuffer: Date?
            recorder.onLevel = { _ in if firstBuffer == nil { firstBuffer = Date() } }
            do {
                try recorder.start()
            } catch {
                print("start failed: \(error)")
                return 3
            }
            let started = Date()
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            let captured = recorder.stop().durationSeconds
            print(String(format: "attempt %d: start() %.0f ms, first audio after %.0f ms, captured %.2f s of 1.50 s",
                         attempt, started.timeIntervalSince(began) * 1000,
                         (firstBuffer ?? Date()).timeIntervalSince(began) * 1000, captured))
            try? await Task.sleep(nanoseconds: 700_000_000)
        }
        return 0
    }
}
