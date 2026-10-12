import AppKit
import UniformTypeIdentifiers
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
        // Occasional use: capture a meeting or a video, or transcribe a file.
        switch controller.recording.state {
        case .idle:
            Button("記録を開始（Mac の音とマイク）") { controller.recording.start() }
            Button("ファイルを文字起こし…") { chooseFile() }
        case .recording(let since):
            Button("記録を停止して文字起こし（\(Self.startTime(since)) 開始）") { controller.recording.stop() }
        case .transcribing(let progress):
            Text("文字起こし中 \(Int(progress * 100))%")
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

    private func chooseFile() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .movie]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { controller.recording.transcribe(file: url) }
    }

    static func startTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func reload() { recent = Array(controller.history.items.prefix(10)) }

    static func title(for item: HistoryItem) -> String {
        let line = item.finalText.replacingOccurrences(of: "\n", with: " ")
        return line.count > 30 ? String(line.prefix(30)) + "…" : line
    }
}
