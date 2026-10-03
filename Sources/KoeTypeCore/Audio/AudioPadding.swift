public enum AudioPadding {
    /// WhisperKit ignores the last second of each decoding window, so an utterance
    /// shorter than that is dropped entirely unless silence follows it.
    public static func withTrailingSilence(_ samples: [Float], sampleRate: Double, seconds: Double) -> [Float] {
        guard !samples.isEmpty else { return samples }
        return samples + [Float](repeating: 0, count: Int(sampleRate * seconds))
    }
}
