import SwiftUI
import KoeTypeCore

struct DictionaryView: View {
    private let store = AppController.shared.dictionary

    @State private var entries: [DictionaryEntry] = []
    @State private var term = ""
    @State private var variants = ""
    @State private var editing: DictionaryEntry?
    @State private var message = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("表記", text: $term).frame(width: 160)
                TextField("読み・誤認識されやすい形（、区切り）", text: $variants)
                Button(editing == nil ? "追加" : "更新") { save() }
                    .keyboardShortcut(.defaultAction)
                if editing != nil { Button("取消") { clear() } }
            }
            if !message.isEmpty {
                Text(message).font(.caption).foregroundStyle(.red)
            }
            List(entries) { entry in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.term)
                        if !entry.variants.isEmpty {
                            Text(entry.variants.joined(separator: "、")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("削除") { try? store.remove(id: entry.id) }
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    editing = entry
                    term = entry.term
                    variants = entry.variants.joined(separator: "、")
                    message = ""
                }
            }
        }
        .padding(14)
        .frame(minWidth: 520, minHeight: 420)
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: DictionaryStore.didChange)
            .receive(on: DispatchQueue.main)) { _ in reload() }
    }

    private func reload() { entries = store.entries }

    private func clear() {
        editing = nil; term = ""; variants = ""; message = ""
    }

    static func parseVariants(_ text: String) -> [String] {
        text.split(whereSeparator: { $0 == "、" || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func save() {
        do {
            if var entry = editing {
                entry.term = term
                entry.variants = Self.parseVariants(variants)
                try store.update(entry)
            } else {
                try store.add(term: term, variants: Self.parseVariants(variants), now: Date())
            }
            clear()
        } catch DictionaryError.emptyTerm {
            message = "表記を入力してください"
        } catch DictionaryError.duplicate {
            message = "同じ表記が既に登録されています"
        } catch {
            message = "保存できませんでした"
        }
    }
}
