import Foundation

public struct HotkeyStateMachine {
    public enum Input: Equatable { case triggerDown, triggerUp, otherKeyDown, escape }
    public enum Action: Equatable { case startRecording, stopAndProcess, cancelRecording, enterHandsFree }

    private enum State: Equatable {
        case idle
        case holding(since: TimeInterval)
        case tapped(releasedAt: TimeInterval)
        case handsFree
        case swallow   // ignore everything until the trigger key is released
    }

    public var minimumHold: TimeInterval = 0.3
    public var doubleTapWindow: TimeInterval = 0.4
    private var state: State = .idle

    public init() {}

    public var isHandsFree: Bool { state == .handsFree }
    public var isRecording: Bool {
        switch state {
        case .holding, .handsFree: return true
        default: return false
        }
    }

    public mutating func reset() { state = .idle }

    public mutating func handle(_ input: Input, at time: TimeInterval) -> [Action] {
        switch (state, input) {
        case (.idle, .triggerDown), (.swallow, .triggerDown):
            state = .holding(since: time)
            return [.startRecording]
        case (.tapped(let releasedAt), .triggerDown):
            if time - releasedAt <= doubleTapWindow {
                state = .handsFree
                return [.startRecording, .enterHandsFree]
            }
            state = .holding(since: time)
            return [.startRecording]
        case (.holding(let since), .triggerUp):
            if time - since < minimumHold {
                state = .tapped(releasedAt: time)
                return [.cancelRecording]
            }
            state = .idle
            return [.stopAndProcess]
        case (.holding, .otherKeyDown), (.holding, .escape):
            state = .swallow
            return [.cancelRecording]
        case (.handsFree, .triggerDown):
            state = .swallow
            return [.stopAndProcess]
        case (.handsFree, .escape):
            state = .idle
            return [.cancelRecording]
        case (.swallow, .triggerUp):
            state = .idle
            return []
        default:
            return []
        }
    }
}
