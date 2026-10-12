/// What a configuration change during a recording means for the user.
public enum MicrophoneChange: Equatable, Sendable {
    /// Still the same microphone, e.g. a Bluetooth headset switching to its call profile: keep recording.
    case sameMicrophone
    /// The microphone in use went away or input moved to another device: end the recording and say so.
    case switched

    /// - Parameters:
    ///   - startedOn: UID of the microphone the recording started on, nil if it could not be read.
    ///   - now: UID of the microphone that would be used now, nil if there is no input at all.
    public static func classify(startedOn: String?, now: String?) -> MicrophoneChange {
        guard let startedOn else { return .sameMicrophone }
        return startedOn == now ? .sameMicrophone : .switched
    }
}
