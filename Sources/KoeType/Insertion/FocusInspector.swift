import AppKit
import ApplicationServices
import KoeTypeCore

enum FocusInspector {
    struct Focus {
        /// nil when the accessibility query itself could not be answered.
        var snapshot: FocusSnapshot?
        var appName: String?
        var element: AXUIElement?
    }

    /// Describes the focused element of the frontmost app.
    static func inspect() -> Focus {
        guard let app = NSWorkspace.shared.frontmostApplication else { return Focus() }
        let appName = app.localizedName
        guard Permissions.accessibilityGranted,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return Focus(snapshot: nil, appName: appName, element: nil)
        }

        let application = AXUIElementCreateApplication(app.processIdentifier)
        // Electron apps expose their accessibility tree only after this is set. Failure is harmless.
        AXUIElementSetAttributeValue(application, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetMessagingTimeout(application, 0.25)

        var focused: CFTypeRef?
        switch AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute as CFString, &focused) {
        case .success:
            guard let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else {
                return Focus(snapshot: nil, appName: appName, element: nil)
            }
            let element = focused as! AXUIElement
            var role: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
            var range: CFTypeRef?
            let hasRange = AXUIElementCopyAttributeValue(
                element, kAXSelectedTextRangeAttribute as CFString, &range) == .success
            let snapshot = FocusSnapshot(
                role: role as? String, hasSelectedTextRange: hasRange,
                isEditable: isSettable(element, kAXValueAttribute) || isSettable(element, kAXSelectedTextRangeAttribute),
                valueLength: length(of: element))
            return Focus(snapshot: snapshot, appName: appName, element: element)
        case .noValue:
            return Focus(snapshot: FocusSnapshot(role: nil, hasSelectedTextRange: false), appName: appName, element: nil)
        default:
            return Focus(snapshot: nil, appName: appName, element: nil)
        }
    }

    /// Number of characters in a text element, or nil when the element does not say.
    static func length(of element: AXUIElement) -> Int? {
        var count: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXNumberOfCharactersAttribute as CFString, &count) == .success,
           let number = count as? Int {
            return number
        }
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
           let text = value as? String {
            return text.count
        }
        return nil
    }

    private static func isSettable(_ element: AXUIElement, _ attribute: String) -> Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success && settable.boolValue
    }
}
