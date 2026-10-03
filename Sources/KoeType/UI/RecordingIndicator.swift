import AppKit
import SwiftUI
import KoeTypeCore

@MainActor
final class RecordingIndicator {
    fileprivate final class Model: ObservableObject {
        @Published var display: IndicatorDisplay = .hidden
        @Published var levels = LevelHistory(capacity: 32)
        @Published var startedAt = Date()
    }

    private let model = Model()
    private lazy var panel = FloatingPanel(size: NSSize(width: 360, height: 44), content: IndicatorView(model: model))

    func set(_ display: IndicatorDisplay) {
        let wasRecording = model.display.isRecording
        model.display = display
        if display.isRecording, !wasRecording {
            model.levels.reset()
            model.startedAt = Date()
        }
        if display == .hidden {
            panel.orderOut(nil)
        } else {
            panel.show(bottomOffset: 24)
        }
    }

    func setLevel(_ level: Float) {
        guard model.display.isRecording else { return }
        model.levels.push(level)
    }
}

private extension IndicatorDisplay {
    var isRecording: Bool {
        if case .recording = self { return true }
        return false
    }
}

private struct IndicatorView: View {
    @ObservedObject var model: RecordingIndicator.Model

    var body: some View {
        HStack(spacing: 10) {
            switch model.display {
            case .recording(let handsFree):
                PulsingDot()
                Waveform(levels: model.levels.values)
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    Text(Self.elapsed(from: model.startedAt, to: context.date))
                        .monospacedDigit()
                }
                Text(caption(handsFree: handsFree))
                    .foregroundStyle(.white.opacity(0.75))
            case .working(let stage):
                ProgressView().controlSize(.small).colorScheme(.dark)
                Text(stage == .transcribing ? "文字に起こしています" : "文章を整えています")
            case .message(let text):
                Text(text)
            case .hidden:
                EmptyView()
            }
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(Capsule().fill(Color.black.opacity(0.85)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12)))
        .fixedSize()
    }

    /// Tells the user whether their voice is actually reaching the app.
    private func caption(handsFree: Bool) -> String {
        if !model.levels.heardSpeech { return "聞き取り中… 話してください" }
        return handsFree ? "もう一度押すと終了" : "離すと入力"
    }

    static func elapsed(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// Bars scroll from right to left; the newest input level is the rightmost bar.
private struct Waveform: View {
    let levels: [Float]

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(levels.indices, id: \.self) { index in
                Capsule()
                    .fill(Color.white.opacity(levels[index] >= LevelHistory.speechFloor ? 1 : 0.45))
                    .frame(width: 2.5, height: 3 + 23 * CGFloat(levels[index]))
            }
        }
        .frame(height: 28)
        .animation(.linear(duration: 0.05), value: levels)
    }
}

private struct PulsingDot: View {
    @State private var dimmed = false

    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 9, height: 9)
            .opacity(dimmed ? 0.35 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { dimmed = true }
            }
    }
}
