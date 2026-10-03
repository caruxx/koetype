import AppKit
import ApplicationServices
import KoeTypeCore

enum FocusInspector {
    /// Describes the focused element of the frontmost app.
    /// `snapshot` is nil when the accessibility query itself could not be answered.
    static func snapshot() -> (snapshot: FocusSnapshot?, appName: String?) {
        guard let app = NSWorkspace.shared.frontmostApplication else { return (nil, nil) }
        let appName = app.localizedName
        guard Permissions.accessibilityGranted,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return (nil, appName)
        }

        let element = AXUIElementCreateApplication(app.processIdentifier)
        // Electron apps expose their accessibility tree only after this is set. Failure is harmless.
        AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetMessagingTimeout(element, 0.25)

        var focused: CFTypeRef?
        switch AXUIElementCopyAttributeValue(element, kAXFocusedUIElementAttribute as CFString, &focused) {
        case .success:
            guard let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return (nil, appName) }
            let target = focused as! AXUIElement
            var role: CFTypeRef?
            AXUIElementCopyAttributeValue(target, kAXRoleAttribute as CFString, &role)
            var range: CFTypeRef?
            let hasRange = AXUIElementCopyAttributeValue(
                target, kAXSelectedTextRangeAttribute as CFString, &range) == .success
            return (FocusSnapshot(role: role as? String, hasSelectedTextRange: hasRange), appName)
        case .noValue:
            return (FocusSnapshot(role: nil, hasSelectedTextRange: false), appName)
        default:
            return (nil, appName)
        }
    }
}
