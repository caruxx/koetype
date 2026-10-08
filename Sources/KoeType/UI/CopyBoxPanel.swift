import AppKit
import SwiftUI

/// Shown when the dictated text could not be inserted into a text field.
@MainActor
final class CopyBoxPanel {
    static let autoCloseSeconds: UInt64 = 30

    fileprivate final class Model: ObservableObject {
        @Published var text = ""
        @Published var message = ""
        var onCopy: () -> Void = {}
        var onClose: () -> Void = {}
    }

    private let model = Model()
    private lazy var panel = FloatingPanel(size: NSSize(width: 420, height: 160), content: CopyBoxView(model: model))
    private var closeTask: Task<Void, Never>?

    init() {
        model.onCopy = { [weak self] in
            guard let self else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(self.model.text, forType: .string)
            self.close()
        }
        model.onClose = { [weak self] in self?.close() }
    }

    func show(text: String, message: String = "入力欄が見つからなかったため、ここに表示しています") {
        model.text = text
        model.message = message
        // Above the recording indicator so the two never overlap.
        panel.show(bottomOffset: 72)
        closeTask?.cancel()
        closeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.autoCloseSeconds * 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.close()
        }
    }

    func close() {
        closeTask?.cancel()
        panel.orderOut(nil)
    }
}

private struct CopyBoxView: View {
    @ObservedObject var model: CopyBoxPanel.Model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            ScrollView {
                Text(model.text)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 160)
            HStack {
                Spacer()
                Button("閉じる") { model.onClose() }
                Button("コピー") { model.onCopy() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 420)
        .background(RoundedRectangle(cornerRadius: 12).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.12)))
    }
}
