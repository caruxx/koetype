import AppKit
import KoeTypeCore

final class HotkeyMonitor {
    /// Marks keyboard events this app posts itself, so its own paste is not mistaken for typing.
    static let syntheticEventTag: Int64 = 0x4B6F6554   // "KoeT"

    var onInput: ((HotkeyStateMachine.Input, TimeInterval) -> Void)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var classifier = HotkeyEventClassifier(trigger: .init(deviceMask: HotkeyChoice.rightCommand.deviceMask))

    func start(choice: HotkeyChoice) -> Bool {
        stop()
        classifier = HotkeyEventClassifier(trigger: .init(deviceMask: choice.deviceMask))
        let types: [CGEventType] = [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown,
                                    .otherMouseDown, .scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << CGEventMask($1.rawValue)) }
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon!).takeUnretainedValue()
            monitor.handle(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .listenOnly, eventsOfInterest: mask,
                                          callback: callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        tap = nil; source = nil
    }

    private func handle(type: CGEventType, event: CGEvent) {
        let now = ProcessInfo.processInfo.systemUptime
        let kind: HotkeyEventClassifier.Kind
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // Events were dropped while the tap was off: a key release may have been missed.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            let flags = CGEventSource.flagsState(.combinedSessionState).rawValue
            if let input = classifier.resync(flags: flags) { emit(input, now) }
            return
        case .flagsChanged: kind = .flagsChanged
        case .keyDown: kind = .keyDown
        case .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel: kind = .pointer
        default: return
        }
        let input = classifier.classify(
            kind, keyCode: UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode)),
            flags: event.flags.rawValue,
            fromSelf: event.getIntegerValueField(.eventSourceUserData) == Self.syntheticEventTag)
        if let input { emit(input, now) }
    }

    /// Handlers start audio and query other apps; keep that out of the tap callback
    /// so the system does not disable the tap for being slow.
    private func emit(_ input: HotkeyStateMachine.Input, _ time: TimeInterval) {
        DispatchQueue.main.async { [weak self] in self?.onInput?(input, time) }
    }
}
