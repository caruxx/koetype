import AppKit
import SwiftUI
import KoeTypeCore

struct HistoryView: View {
    private let store = AppController.shared.history

    @State private var query = ""
    @State private var items: [HistoryItem] = []

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter
    }()

    var body: some View {
        VStack(spacing: 8) {
            TextField("検索", text: $query)
                .textFieldStyle(.roundedBorder)
                .onChange(of: query) { reload() }
            if items.isEmpty {
                Spacer()
                Text("該当する履歴がありません").foregroundStyle(.secondary)
                Spacer()
            } else {
                List(items) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(Self.dateFormatter.string(from: item.date))
                            if let app = item.appName { Text(app) }
                            Text(Self.label(for: item))
                            Spacer()
                            Button("コピー") { copy(item.finalText) }
                            Button("整形前をコピー") { copy(item.rawText) }
                            Button("削除") { try? store.remove(id: item.id) }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        Text(item.finalText).lineLimit(3).textSelection(.enabled)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(14)
        .frame(minWidth: 640, minHeight: 480)
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: HistoryStore.didChange)
            .receive(on: DispatchQueue.main)) { _ in reload() }
    }

    private func reload() { items = store.search(query) }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static func label(for item: HistoryItem) -> String {
        let outcome: String
        switch item.outcome {
        case .inserted: outcome = "挿入"
        case .copyBox: outcome = "コピーボックス"
        case .insertedAndCopyBox: outcome = "挿入 + コピーボックス"
        }
        return outcome + (item.polished ? "・AI 整形" : "・ローカル処理")
    }
}
