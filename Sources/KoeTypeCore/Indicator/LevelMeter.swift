public enum LevelMeter {
    /// Maps a raw RMS amplitude to 0...1 for display. Speech is far quieter than full scale,
    /// so a square-root curve keeps ordinary talking clearly visible.
    public static func display(rms: Float) -> Float {
        guard rms > 0 else { return 0 }
        return min(1, rms.squareRoot() * 2.6)
    }
}

/// The most recent input levels, oldest first, for drawing a scrolling waveform.
public struct LevelHistory: Equatable, Sendable {
    /// Display level above which the input is taken to be a voice rather than room noise.
    public static let speechFloor: Float = 0.25

    public private(set) var values: [Float]
    public private(set) var heardSpeech = false

    public init(capacity: Int) { values = [Float](repeating: 0, count: capacity) }

    public mutating func push(_ level: Float) {
        values.removeFirst()
        values.append(level)
        if level >= Self.speechFloor { heardSpeech = true }
    }

    public mutating func reset() {
        values = [Float](repeating: 0, count: values.count)
        heardSpeech = false
    }
}
