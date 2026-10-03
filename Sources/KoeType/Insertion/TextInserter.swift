import AppKit
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
        let ourChangeCount = pasteboard.changeCount

        let source = CGEventSource(stateID: .combinedSessionState)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: keyDown)   // 9 = V
            event?.flags = .maskCommand   // explicit: ignore a trigger key the user may be holding again
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
}
