import SwiftUI

struct OnboardingView: View {
    @ObservedObject private var controller = AppController.shared
    @State private var accessibilityGranted = Permissions.accessibilityGranted

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("KoeType を使うには、次の準備が必要です。")
            row("マイク", done: controller.microphoneGranted, detail: controller.microphoneGranted ? "許可済み" : "未許可") {
                Button("許可する") {
                    Task {
                        if await !Permissions.requestMicrophone() { Permissions.openSettings(.microphone) }
                        controller.refreshPermissions()
                    }
                }
            }
            row("アクセシビリティ", done: accessibilityGranted, detail: accessibilityGranted ? "許可済み" : "未許可") {
                Button("設定を開く") { Permissions.promptAccessibility() }
            }
            row("音声認識モデル", done: controller.transcriber.state == .ready, detail: modelText) { EmptyView() }
            Divider()
            if controller.isReady {
                Text("準備ができました。\(controller.settings.hotkey.label) を押しながら話してください。")
                HStack {
                    Spacer()
                    Button("閉じる") { WindowManager.shared.close(id: "onboarding") }
                }
            } else {
                Text("ホットキーの監視と文章の貼り付けにアクセシビリティの許可を使います。音声は Mac の外に送信されません。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(minWidth: 460, minHeight: 300)
        .onReceive(timer) { _ in
            accessibilityGranted = Permissions.accessibilityGranted
            controller.refreshPermissions()
        }
    }

    private var modelText: String {
        switch controller.transcriber.state {
        case .notLoaded: return "準備中"
        case .downloading(let progress): return "ダウンロード中 \(Int(progress * 100))%"
        case .loading: return "読み込み中"
        case .ready: return "準備完了"
        case .failed: return "読み込みに失敗しました"
        }
    }

    private func row<Action: View>(_ name: String, done: Bool, detail: String,
                                   @ViewBuilder action: () -> Action) -> some View {
        HStack {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? Color.green : Color.secondary)
            Text(name)
            Spacer()
            Text(detail).foregroundStyle(.secondary)
            if !done { action() }
        }
    }
}
