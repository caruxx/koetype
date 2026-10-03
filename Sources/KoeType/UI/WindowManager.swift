import AppKit
import SwiftUI

/// Opens the app's ordinary windows. A menu bar app has no Dock icon, so each window
/// is created on demand and the app is activated explicitly to bring it to the front.
@MainActor
final class WindowManager {
    static let shared = WindowManager()
    private var windows: [String: NSWindow] = [:]

    func show<Content: View>(id: String, title: String, size: NSSize, @ViewBuilder content: () -> Content) {
        if windows[id] == nil {
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = title
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: content())
            window.setContentSize(size)
            window.center()
            windows[id] = window
        }
        NSApp.activate(ignoringOtherApps: true)
        windows[id]?.makeKeyAndOrderFront(nil)
    }

    func close(id: String) { windows[id]?.close() }

    func showSettings() {
        show(id: "settings", title: "KoeType 設定", size: NSSize(width: 480, height: 400)) { SettingsView() }
    }
    func showDictionary() {
        show(id: "dictionary", title: "辞書", size: NSSize(width: 520, height: 420)) { DictionaryView() }
    }
    func showHistory() {
        show(id: "history", title: "履歴", size: NSSize(width: 640, height: 480)) { HistoryView() }
    }
    /// Each transcript replaces the previous one in the same window.
    func showTranscript(text: String, file: URL?) {
        windows["transcript"]?.close()
        windows["transcript"] = nil
        show(id: "transcript", title: "文字起こし", size: NSSize(width: 640, height: 520)) {
            TranscriptView(text: text, file: file)
        }
    }

    func showAppStyles() {
        show(id: "appStyles", title: "アプリ別の文体", size: NSSize(width: 500, height: 460)) { AppStylesView() }
    }

    func showOnboarding() {
        show(id: "onboarding", title: "KoeType へようこそ", size: NSSize(width: 460, height: 300)) { OnboardingView() }
    }
}
