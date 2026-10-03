import AppKit
import SwiftUI

@MainActor
final class RecordingIndicator {
    enum Mode: Equatable { case hidden, recording(handsFree: Bool), processing, message(String) }

    fileprivate final class Model: ObservableObject {
        @Published var mode: Mode = .hidden
        @Published var level: Float = 0
    }

    private let model = Model()
    private lazy var panel = FloatingPanel(size: NSSize(width: 320, height: 36), content: IndicatorView(model: model))
    private var hideTask: Task<Void, Never>?

    func set(_ mode: Mode) {
        hideTask?.cancel()
        model.mode = mode
        switch mode {
        case .hidden:
            panel.orderOut(nil)
        case .message:
            panel.show(bottomOffset: 24)
            hideTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { return }
                self?.set(.hidden)
            }
        default:
            panel.show(bottomOffset: 24)
        }
    }

    func setLevel(_ level: Float) { model.level = level }
}

private struct IndicatorView: View {
    @ObservedObject var model: RecordingIndicator.Model

    var body: some View {
        HStack(spacing: 8) {
            switch model.mode {
            case .recording(let handsFree):
                LevelBars(level: model.level)
                Text(handsFree ? "ハンズフリー録音中（もう一度押すと終了）" : "録音中")
            case .processing:
                ProgressView().controlSize(.small)
                Text("処理中")
            case .message(let text):
                Text(text)
            case .hidden:
                EmptyView()
            }
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background(Capsule().fill(Color.black.opacity(0.82)))
        .fixedSize()
    }
}

private struct LevelBars: View {
    let level: Float
    private let weights: [CGFloat] = [0.5, 0.8, 1.0, 0.8, 0.5]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(weights.indices, id: \.self) { index in
                Capsule()
                    .fill(Color.red)
                    .frame(width: 3, height: 4 + 16 * CGFloat(level) * weights[index])
            }
        }
        .frame(height: 20)
        .animation(.easeOut(duration: 0.08), value: level)
    }
}
