import SwiftUI
import KoeTypeCore

struct KoeTypeApp: App {
    var body: some Scene {
        MenuBarExtra("KoeType", systemImage: "mic") {
            Text("KoeType \(KoeTypeCore.version)")
            Divider()
            Button("終了") { NSApplication.shared.terminate(nil) }
        }
    }
}
