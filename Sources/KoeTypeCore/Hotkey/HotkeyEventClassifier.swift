import Foundation

/// Turns raw keyboard and pointer events into hotkey inputs.
/// Works on the device-specific modifier bits so the left and right keys are told apart.
public struct HotkeyEventClassifier {
    public enum Kind: Equatable { case flagsChanged, keyDown, pointer }

    public struct Trigger: Equatable, Sendable {
        /// Bit in the raw event flags that is set only while the trigger key itself is down.
        public var deviceMask: UInt64
        public init(deviceMask: UInt64) { self.deviceMask = deviceMask }
    }

    /// Left/right control, shift, command and option device bits.
    static let allDeviceModifiers: UInt64 = 0x1 | 0x2 | 0x4 | 0x8 | 0x10 | 0x20 | 0x40 | 0x2000
    static let escapeKeyCode: UInt16 = 53

    private let trigger: Trigger
    private var triggerIsDown = false
    private var otherModifiers: UInt64 = 0

    public init(trigger: Trigger) { self.trigger = trigger }

    /// - Parameter fromSelf: the event was posted by this app (its own paste keystroke).
    public mutating func classify(_ kind: Kind, keyCode: UInt16, flags: UInt64,
                                  fromSelf: Bool) -> HotkeyStateMachine.Input? {
        guard !fromSelf else { return nil }
        switch kind {
        case .keyDown:
            return keyCode == Self.escapeKeyCode ? .escape : .otherKeyDown
        case .pointer:
            return .otherKeyDown
        case .flagsChanged:
            let others = flags & Self.allDeviceModifiers & ~trigger.deviceMask
            let newlyPressed = others & ~otherModifiers
            otherModifiers = others
            let down = flags & trigger.deviceMask != 0
            if down != triggerIsDown {
                triggerIsDown = down
                return down ? .triggerDown : .triggerUp
            }
            return newlyPressed != 0 ? .otherKeyDown : nil
        }
    }

    /// Call with the current modifier flags after events may have been dropped.
    public mutating func resync(flags: UInt64) -> HotkeyStateMachine.Input? {
        otherModifiers = flags & Self.allDeviceModifiers & ~trigger.deviceMask
        guard triggerIsDown, flags & trigger.deviceMask == 0 else { return nil }
        triggerIsDown = false
        return .triggerUp
    }
}
