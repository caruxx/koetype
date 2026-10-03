import SwiftUI
import KoeTypeCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppController.shared.start()
        if CommandLine.arguments.contains("--open-settings") { WindowManager.shared.showSettings() }
        if CommandLine.arguments.contains("--open-app-styles") { WindowManager.shared.showAppStyles() }
    }
}

struct KoeTypeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var controller = AppController.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent(controller: controller)
        } label: {
            Image(systemName: controller.recording.isRecording ? "record.circle"
                  : controller.isReady ? "mic" : "mic.slash")
        }
    }
}
