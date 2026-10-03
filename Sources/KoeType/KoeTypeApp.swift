import SwiftUI
import KoeTypeCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppController.shared.start()
    }
}

struct KoeTypeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var controller = AppController.shared

    var body: some Scene {
        MenuBarExtra {
            Text(controller.statusText)
            Divider()
            Button("終了") { NSApplication.shared.terminate(nil) }
        } label: {
            Image(systemName: controller.isReady ? "mic" : "mic.slash")
        }
    }
}
