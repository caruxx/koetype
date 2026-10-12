import AppKit
import KoeTypeCore

final class HotkeyMonitor {
    /// Marks keyboard events this app posts itself, so its own paste is not mistaken for typing.
    static let syntheticEventTag: Int64 = 0x4B6F6554   // "KoeT"

    var onInput: ((HotkeyStateMachine.Input, TimeInterval) -> Void)?
    /// The tap was recreated on its own (after sleep, or once permission came back) or could not be.
    var onActiveChange: ((Bool) -> Void)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    /// The key the app asked for; nil until `start` is called and again after `stop`.
    private var choice: HotkeyChoice?
    private var watchdog: Timer?
    private var wakeObservers: [NSObjectProtocol] = []
    private static let watchdogInterval: TimeInterval = 3
    private var classifier = HotkeyEventClassifier(trigger: .init(deviceMask: HotkeyChoice.rightCommand.deviceMask))

    func start(choice: HotkeyChoice) -> Bool {
        stop()
        self.choice = choice
        startWatching()
        return createTap(choice: choice)
    }

    func stop() {
        choice = nil
        removeTap()
    }

    private func createTap(choice: HotkeyChoice) -> Bool {
        removeTap()
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

    private func removeTap() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        tap = nil; source = nil
    }

    /// The system can switch a tap off, or leave it dead after sleep or a permission change,
    /// without the app being told. Check on it now and then and rebuild it when needed.
    private func startWatching() {
        guard watchdog == nil else { return }
        let timer = Timer(timeInterval: Self.watchdogInterval, repeats: true) { [weak self] _ in
            self?.checkTap()
        }
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.sessionDidBecomeActiveNotification] {
            wakeObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.rebuild()
            })
        }
    }

    private func checkTap() {
        guard choice != nil else { return }
        guard let tap, CFMachPortIsValid(tap) else { return rebuild() }
        guard !CGEvent.tapIsEnabled(tap: tap) else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
        if CGEvent.tapIsEnabled(tap: tap) { resync() } else { rebuild() }
    }

    private func rebuild() {
        guard let choice else { return }
        // A release may have been missed while the tap was dead; settle it before the classifier is replaced.
        resync()
        let wasActive = tap != nil
        let active = createTap(choice: choice)
        if active != wasActive { onActiveChange?(active) }
    }

    private func resync() {
        let flags = CGEventSource.flagsState(.combinedSessionState).rawValue
        if let input = classifier.resync(flags: flags) { emit(input, ProcessInfo.processInfo.systemUptime) }
    }

    private func handle(type: CGEventType, event: CGEvent) {
        let now = ProcessInfo.processInfo.systemUptime
        let kind: HotkeyEventClassifier.Kind
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // Events were dropped while the tap was off: a key release may have been missed.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            resync()
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
