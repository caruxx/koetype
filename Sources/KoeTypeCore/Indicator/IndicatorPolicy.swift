public enum IndicatorStage: Equatable, Sendable { case transcribing, polishing }

public enum IndicatorDisplay: Equatable, Sendable {
    case hidden
    case recording(handsFree: Bool)
    case working(IndicatorStage)
    case message(String)
}

public enum RecordingState: Equatable, Sendable { case none, holding, handsFree }

public enum IndicatorPolicy {
    /// Decides the one thing the indicator shows. Recording comes first, then a message
    /// that has not yet had its time on screen, then work still in progress.
    public static func display(recording: RecordingState, message: String?, pending: Int,
                               stage: IndicatorStage) -> IndicatorDisplay {
        switch recording {
        case .holding: return .recording(handsFree: false)
        case .handsFree: return .recording(handsFree: true)
        case .none: break
        }
        if let message { return .message(message) }
        return pending > 0 ? .working(stage) : .hidden
    }
}
