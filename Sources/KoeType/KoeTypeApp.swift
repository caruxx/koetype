import SwiftUI
import KoeTypeCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Opening the app again (Spotlight, Finder, Launchpad) shows the settings window, so the app
    /// stays reachable even when its menu bar icon is hidden by the notch or a menu bar organiser.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        WindowManager.shared.showSettings()
        return false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppController.shared.start()
        if CommandLine.arguments.contains("--open-settings") { WindowManager.shared.showSettings() }
        if CommandLine.arguments.contains("--open-app-styles") { WindowManager.shared.showAppStyles() }
        if CommandLine.arguments.contains("--open-mic-compare") { WindowManager.shared.showMicrophoneComparison() }
    }
}

struct KoeTypeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var controller = AppController.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent(controller: controller)
        } label: {
            // The same waveform as the app icon, so it can be told apart from other microphone icons.
            Image(systemName: controller.recording.isRecording ? "record.circle"
                  : controller.isReady ? "waveform" : "waveform.slash")
        }
    }
}
