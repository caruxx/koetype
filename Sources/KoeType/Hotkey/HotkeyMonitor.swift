import AppKit
import KoeTypeCore

final class HotkeyMonitor {
    var onInput: ((HotkeyStateMachine.Input, TimeInterval) -> Void)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var choice: HotkeyChoice = .rightOption
    private var triggerIsDown = false

    func start(choice: HotkeyChoice) -> Bool {
        stop()
        self.choice = choice
        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon!).takeUnretainedValue()
            monitor.handle(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .listenOnly, eventsOfInterest: CGEventMask(mask),
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
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil; triggerIsDown = false
    }

    private func handle(type: CGEventType, event: CGEvent) {
        let now = ProcessInfo.processInfo.systemUptime
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .flagsChanged:
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            if keyCode == choice.keyCode {
                let down = event.flags.contains(choice.flag)
                guard down != triggerIsDown else { return }
                triggerIsDown = down
                onInput?(down ? .triggerDown : .triggerUp, now)
            } else if !event.flags.intersection([.maskShift, .maskControl, .maskAlternate, .maskCommand]).isEmpty {
                onInput?(.otherKeyDown, now)   // another modifier pressed while holding the trigger
            }
        case .keyDown:
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            onInput?(keyCode == 53 ? .escape : .otherKeyDown, now)
        default:
            break
        }
    }
}
