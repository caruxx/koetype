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
    static let panelWidth: CGFloat = 520
    static let panelHeight: CGFloat = 76
    private lazy var panel = FloatingPanel(size: NSSize(width: RecordingIndicator.panelWidth,
                                                        height: RecordingIndicator.panelHeight),
                                           content: IndicatorView(model: model))

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
            panel.show(bottomOffset: 10)
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

    /// The pill never changes size, whatever it shows, so nothing on screen jumps.
    static let pillSize = CGSize(width: 400, height: 46)

    var body: some View {
        content
            .font(.system(size: 12.5, weight: .medium, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(width: Self.pillSize.width, height: Self.pillSize.height)
            .background {
                ZStack {
                    // Blurs whatever is behind the pill, then darkens it enough for white text.
                    BehindWindowBlur()
                    LinearGradient(colors: [Color.black.opacity(0.38), Color.black.opacity(0.52)],
                                   startPoint: .top, endPoint: .bottom)
                }
                .clipShape(Capsule())
            }
            .overlay {
                Capsule().strokeBorder(
                    LinearGradient(colors: [Color.white.opacity(0.38), Color.white.opacity(0.08)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.28), radius: 10, y: 4)
            // The window is wider and taller than the pill: room for the shadow, and the pill
            // stays centred on screen.
            .frame(width: RecordingIndicator.panelWidth, height: RecordingIndicator.panelHeight)
            .environment(\.colorScheme, .dark)
    }

    @ViewBuilder private var content: some View {
        switch model.display {
        case .recording(let handsFree):
            HStack(spacing: 12) {
                PulsingDot()
                Waveform(levels: model.levels.values)
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    Text(Self.elapsed(from: model.startedAt, to: context.date))
                        .monospacedDigit()
                        .frame(width: 34, alignment: .trailing)
                }
                Text(caption(handsFree: handsFree))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
                    .frame(width: 116, alignment: .leading)
            }
        case .working(let stage):
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(stage == .transcribing ? "文字に起こしています" : "文章を整えています")
            }
        case .message(let text):
            Text(text).lineLimit(1).minimumScaleFactor(0.8)
        case .hidden:
            EmptyView()
        }
    }

    /// Tells the user whether their voice is actually reaching the app.
    private func caption(handsFree: Bool) -> String {
        if !model.levels.heardSpeech { return "お話しください" }
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
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(levels.indices, id: \.self) { index in
                let level = CGFloat(levels[index])
                let voiced = levels[index] >= LevelHistory.speechFloor
                Capsule()
                    .fill(LinearGradient(
                        colors: voiced ? [Color(red: 0.62, green: 0.90, blue: 1.0), .white]
                                       : [Color.white.opacity(0.35), Color.white.opacity(0.35)],
                        startPoint: .bottom, endPoint: .top))
                    .frame(width: 2.5, height: 3 + 23 * level)
                    // Older bars fade out toward the left edge.
                    .opacity(0.6 + 0.4 * Double(index) / Double(max(1, levels.count - 1)))
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
            .fill(Color(red: 1.0, green: 0.27, blue: 0.23))
            .frame(width: 9, height: 9)
            .shadow(color: Color.red.opacity(0.8), radius: dimmed ? 1 : 5)
            .opacity(dimmed ? 0.45 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { dimmed = true }
            }
    }
}

/// System blur of the content behind the window (SwiftUI materials only blur within the window).
private struct BehindWindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .vibrantDark)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
