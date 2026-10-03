import AppKit
import SwiftUI
import KoeTypeCore

struct MenuContent: View {
    @ObservedObject var controller: AppController
    @State private var recent: [HistoryItem] = []

    var body: some View {
        Text(controller.statusText)
        Divider()
        Text("最近の入力")
        if recent.isEmpty {
            Text("まだ履歴がありません")
        } else {
            ForEach(recent) { item in
                Button(Self.title(for: item)) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.finalText, forType: .string)
                }
            }
        }
        Divider()
        Button("履歴を開く") { WindowManager.shared.showHistory() }
        Button("辞書を開く") { WindowManager.shared.showDictionary() }
        Button("設定を開く") { WindowManager.shared.showSettings() }
        Divider()
        Button("終了") { NSApplication.shared.terminate(nil) }
            .onAppear(perform: reload)
            .onReceive(NotificationCenter.default.publisher(for: HistoryStore.didChange)
                .receive(on: DispatchQueue.main)) { _ in reload() }
    }

    private func reload() { recent = Array(controller.history.items.prefix(10)) }

    static func title(for item: HistoryItem) -> String {
        let line = item.finalText.replacingOccurrences(of: "\n", with: " ")
        return line.count > 30 ? String(line.prefix(30)) + "…" : line
    }
}
