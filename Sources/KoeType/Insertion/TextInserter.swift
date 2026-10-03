import AppKit
import Carbon.HIToolbox
import KoeTypeCore

final class TextInserter: TextDelivering, @unchecked Sendable {
    private let copyBox: CopyBoxPanel
    init(copyBox: CopyBoxPanel) { self.copyBox = copyBox }

    func deliver(_ text: String) async -> DeliveryResult {
        await MainActor.run { () -> DeliveryResult in
            let (snapshot, appName) = FocusInspector.snapshot()
            switch InsertionDecision.plan(for: snapshot) {
            case .pasteOnly:
                paste(text)
                return DeliveryResult(outcome: .inserted, appName: appName)
            case .copyBoxOnly:
                copyBox.show(text: text)
                return DeliveryResult(outcome: .copyBox, appName: appName)
            case .pasteAndCopyBox:
                paste(text)
                copyBox.show(text: text)
                return DeliveryResult(outcome: .insertedAndCopyBox, appName: appName)
            }
        }
    }

    @MainActor private func paste(_ text: String) {
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

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
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
