import AppKit
import KoeTypeCore

enum IndicatorPreview {
    @MainActor private static var indicator: RecordingIndicator?

    static func run() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                let indicator = RecordingIndicator()
                Self.indicator = indicator
                indicator.set(.recording(handsFree: false))
                var tick = 0
                Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
                    MainActor.assumeIsolated {
                        tick += 1
                        // One second of silence, then speech-like bursts.
                        let speaking = tick > 20 && (tick / 12) % 3 != 2
                        let level = speaking ? 0.35 + 0.5 * abs(sin(Float(tick) * 0.9)) : 0.04
                        indicator.setLevel(level)
                        if tick == 120 { indicator.set(.working(.transcribing)) }
                        if tick == 160 { exit(0) }
                    }
                }
            }
        }
        app.run()
        exit(0)
    }
}
