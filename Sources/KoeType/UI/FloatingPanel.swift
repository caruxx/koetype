import AppKit
import SwiftUI

/// Borderless panel that floats above other apps without taking focus from them.
final class FloatingPanel: NSPanel {
    init<Content: View>(size: NSSize, content: Content) {
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false   // content draws its own outline; a window shadow would trace the invisible frame
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = NSHostingView(rootView: content)
    }

    override var canBecomeKey: Bool { true }

    /// Places the panel at the bottom centre of the screen the mouse is on.
    func show(bottomOffset: CGFloat) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            if let fitting = contentView?.fittingSize, fitting.height > 0 { setContentSize(fitting) }
            setFrameOrigin(NSPoint(x: visible.midX - frame.width / 2, y: visible.minY + bottomOffset))
        }
        orderFrontRegardless()
    }
}
