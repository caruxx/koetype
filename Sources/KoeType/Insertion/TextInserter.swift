import AppKit
import Carbon.HIToolbox
import KoeTypeCore

final class TextInserter: TextDelivering, @unchecked Sendable {
    private let copyBox: CopyBoxPanel
    init(copyBox: CopyBoxPanel) { self.copyBox = copyBox }

    func deliver(_ text: String) async -> DeliveryResult {
        await deliverOnMain(text)
    }

    @MainActor private func deliverOnMain(_ text: String) async -> DeliveryResult {
        let focus = await FocusInspector.inspect()
        let plan = InsertionDecision.plan(for: focus.snapshot)
        let outcome: DeliveryOutcome
        var verified: Bool?
        switch plan {
        case .copyBoxOnly:
            copyBox.show(text: text)
            outcome = .copyBox
        case .pasteOnly:
            let restore = paste(text)
            await pause(Self.settleSeconds)
            restore()
            outcome = .inserted
        case .pasteAndCopyBox:
            let restore = paste(text)
            copyBox.show(text: text)
            await pause(Self.settleSeconds)
            restore()
            outcome = .insertedAndCopyBox
        case .pasteThenVerify:
            let before = focus.snapshot?.valueLength ?? 0
            let restore = paste(text)
            var inserted = false
            // Slow apps take a few hundred milliseconds to act on the paste.
            for _ in 0..<10 where !inserted {
                await pause(0.1)
                inserted = InsertionDecision.didInsert(
                    lengthBefore: before, lengthAfter: focus.element.flatMap(FocusInspector.length(of:)))
            }
            if !inserted { copyBox.show(text: text) }
            await pause(0.2)
            restore()
            verified = inserted
            outcome = inserted ? .inserted : .copyBox
        }
        InsertionLog.record(app: focus.appName, snapshot: focus.snapshot, plan: plan, verified: verified)
        return DeliveryResult(outcome: outcome, appName: focus.appName)
    }

    /// How long the dictated text stays on the clipboard before the previous content returns.
    /// Electron and browser apps read the clipboard noticeably later than the key event.
    private static let settleSeconds = 0.8

    private func pause(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    /// Puts the text on the clipboard and sends the paste shortcut.
    /// Returns a closure that puts the previous clipboard content back.
    @MainActor private func paste(_ text: String) -> () -> Void {
        let pasteboard = NSPasteboard.general
        // Keep every type of every item so images and files survive, not only strings.
        let saved: [[(NSPasteboard.PasteboardType, Data)]] = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        // Clipboard managers skip entries carrying this marker (nspasteboard.org convention).
        pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        let ourChangeCount = pasteboard.changeCount

        let source = CGEventSource(stateID: .combinedSessionState)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: Self.pasteKeyCode, keyDown: keyDown)
            event?.flags = .maskCommand   // explicit: ignore a trigger key the user may be holding again
            event?.setIntegerValueField(.eventSourceUserData, value: HotkeyMonitor.syntheticEventTag)
            event?.post(tap: .cghidEventTap)
        }

        return {
            guard ClipboardRestorePolicy.shouldRestore(changeCountAfterOurWrite: ourChangeCount,
                                                       currentChangeCount: pasteboard.changeCount) else { return }
            pasteboard.clearContents()
            let items = saved.map { entries -> NSPasteboardItem in
                let item = NSPasteboardItem()
                for (type, data) in entries { item.setData(data, forType: type) }
                return item
            }
            if !items.isEmpty { pasteboard.writeObjects(items) }
        }
    }

    /// Virtual key that types "v" in the current keyboard layout (9 on QWERTY, different on Dvorak).
    private static var pasteKeyCode: CGKeyCode {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return 9 }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        return data.withUnsafeBytes { buffer -> CGKeyCode in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return 9 }
            for keyCode in UInt16(0)..<128 {
                var deadKeys: UInt32 = 0
                var length = 0
                var characters = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()),
                                            OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys,
                                            characters.count, &length, &characters)
                if status == noErr, length == 1, characters[0] == UniChar(ascii: "v") { return keyCode }
            }
            return 9
        }
    }
}

private extension UniChar {
    init(ascii character: Character) { self = UniChar(character.asciiValue ?? 0) }
}
