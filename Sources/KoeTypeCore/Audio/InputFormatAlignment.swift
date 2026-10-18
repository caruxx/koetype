import Foundation

/// Whether the input node's output format has to be set to the hardware's. Pointing an engine's input at
/// a chosen microphone leaves the node's output format at what the previous device had: the input node
/// does not convert sample rates, so a tap that follows that stale format makes the start fail with
/// -10868 (a Bluetooth headset in its 16 kHz call profile behind a 48 kHz format).
public enum InputFormatAlignment {
    /// - Parameters:
    ///   - pointedAtDevice: the engine was pointed at a chosen microphone. One that follows the system
    ///     default is never touched: AVAudioEngine keeps its formats in step by itself.
    public static func needed(pointedAtDevice: Bool, hardwareRate: Double, hardwareChannels: UInt32,
                              outputRate: Double, outputChannels: UInt32) -> Bool {
        guard pointedAtDevice, hardwareRate > 0, hardwareChannels > 0 else { return false }
        return hardwareRate != outputRate || hardwareChannels != outputChannels
    }
}
