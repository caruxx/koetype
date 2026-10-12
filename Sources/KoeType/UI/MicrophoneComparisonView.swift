import SwiftUI
import KoeTypeCore

/// Records the same utterance through every connected microphone at once and shows what each
/// one was heard as, so the choice of microphone can rest on the user's own voice.
struct MicrophoneComparisonView: View {
    private struct Result: Identifiable {
        let id: String
        let name: String
        let text: String
        let peak: Float
    }

    private static let seconds = 8

    @ObservedObject private var settings = AppSettings.shared
    @State private var results: [Result] = []
    @State private var remaining = 0
    @State private var working = false
    @State private var message = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ボタンを押して、普段どおりの話し方で \(Self.seconds) 秒間話してください。接続中のマイクすべてで同時に録音し、それぞれの聞き取り結果を並べます。録音は比較が終わると破棄します。")
                .font(.callout)
            HStack {
                Button(remaining > 0 ? "録音中… あと \(remaining) 秒" : "\(Self.seconds) 秒間録音して比べる") { run() }
                    .disabled(working)
                if working && remaining == 0 { ProgressView().controlSize(.small) }
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            List(results) { result in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(result.name).bold()
                        Spacer()
                        Text(String(format: "音量の最大 %.2f", result.peak)).font(.caption).foregroundStyle(.secondary)
                        Button("このマイクを使う") { settings.microphone = .device(uid: result.id) }
                            .disabled(settings.microphone == .device(uid: result.id))
                    }
                    Text(result.text.isEmpty ? "（聞き取れませんでした）" : result.text).textSelection(.enabled)
                }
                .padding(.vertical, 3)
            }
        }
        .padding(14)
        .frame(minWidth: 560, minHeight: 420)
    }

    private func run() {
        let transcriber = AppController.shared.transcriber
        guard transcriber.isReady else {
            message = "音声認識モデルを準備中です"
            return
        }
        // Phone microphones offered through Continuity would wake the phone; leave them out.
        let devices = AudioDevices.inputs().map(\.device).filter { !$0.name.contains("iPhone") }
        var recorders: [(device: AudioInputDevice, recorder: AudioRecorder)] = []
        for device in devices {
            let recorder = AudioRecorder()
            recorder.preference = { .device(uid: device.uid) }
            if (try? recorder.start()) != nil { recorders.append((device, recorder)) }
        }
        guard !recorders.isEmpty else {
            message = "録音できるマイクがありません"
            return
        }
        working = true
        results = []
        message = ""
        remaining = Self.seconds
        Task {
            while remaining > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                remaining -= 1
            }
            var collected: [Result] = []
            for entry in recorders {
                let samples = entry.recorder.stop().samples
                let text = (try? await transcriber.transcribe(samples: samples, hints: "")) ?? ""
                collected.append(Result(id: entry.device.uid, name: entry.device.name,
                                        text: HallucinationFilter.clean(text),
                                        peak: samples.map { abs($0) }.max() ?? 0))
            }
            results = collected
            working = false
        }
    }
}
