import ServiceManagement
import SwiftUI
import KoeTypeCore

struct SettingsView: View {
    @ObservedObject private var controller = AppController.shared
    @ObservedObject private var settings = AppSettings.shared

    @State private var whisperModelDraft = AppSettings.shared.whisperModel
    @State private var apiKeyDraft = ""
    @State private var hasAPIKey = KeychainStore.readAPIKey() != nil
    @State private var keyMessage = ""
    @State private var availableModels: [String] = []
    @State private var testMessage = ""
    @State private var testing = false
    @State private var loginMessage = ""
    @State private var accessibilityGranted = Permissions.accessibilityGranted

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section("入力") {
                Picker("ホットキー", selection: $settings.hotkey) {
                    ForEach(HotkeyChoice.allCases) { Text($0.label).tag($0) }
                }
                .onChange(of: settings.hotkey) { controller.reloadHotkey() }
                Text("押している間だけ録音します。素早く 2 回押すとハンズフリー、もう一度押すと終了します。Esc で取り消します。")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("音声認識") {
                TextField("モデル名", text: $whisperModelDraft)
                HStack {
                    Button("適用") {
                        settings.whisperModel = whisperModelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        controller.reloadModel()
                    }
                    Button("既定に戻す") {
                        whisperModelDraft = AppSettings.defaultWhisperModel
                        settings.whisperModel = AppSettings.defaultWhisperModel
                        controller.reloadModel()
                    }
                    Spacer()
                    Text(modelStateText).foregroundStyle(.secondary)
                }
            }

            Section("整形") {
                Toggle("AI で整形する", isOn: $settings.polishEnabled)
                TextField("モデル ID", text: $settings.polishModel)
                HStack {
                    Button("モデル一覧を取得") { fetchModels() }
                    if !availableModels.isEmpty {
                        Picker("", selection: $settings.polishModel) {
                            ForEach(availableModels, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                    }
                }
                SecureField(hasAPIKey ? "API キー（保存済み）" : "API キー", text: $apiKeyDraft)
                HStack {
                    Button("保存") { saveKey(apiKeyDraft) }
                        .disabled(apiKeyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("削除") { saveKey("") }.disabled(!hasAPIKey)
                    Spacer()
                    Text(keyMessage).foregroundStyle(.secondary)
                }
                HStack {
                    Button("接続テスト") { runTest() }.disabled(testing)
                    if testing { ProgressView().controlSize(.small) }
                }
                if !testMessage.isEmpty {
                    Text(testMessage).font(.caption).textSelection(.enabled)
                }
            }

            Section("一般") {
                Toggle("ログイン時に起動", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { setLaunchAtLogin($0) }))
                if !loginMessage.isEmpty {
                    Text(loginMessage).font(.caption).foregroundStyle(.red)
                }
                permissionRow("マイク", granted: controller.microphoneGranted, pane: .microphone)
                permissionRow("アクセシビリティ", granted: accessibilityGranted, pane: .accessibility)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 520, minHeight: 560)
        .onReceive(timer) { _ in
            accessibilityGranted = Permissions.accessibilityGranted
            controller.refreshPermissions()
        }
    }

    private var modelStateText: String {
        switch controller.transcriber.state {
        case .notLoaded: return "未読み込み"
        case .downloading(let progress): return "ダウンロード中 \(Int(progress * 100))%"
        case .loading: return "読み込み中"
        case .ready: return "準備完了"
        case .failed(let message): return "失敗: \(message)"
        }
    }

    private func permissionRow(_ name: String, granted: Bool, pane: Permissions.Pane) -> some View {
        HStack {
            Text(name)
            Spacer()
            Text(granted ? "許可済み" : "未許可").foregroundStyle(granted ? Color.secondary : Color.red)
            Button("設定を開く") { Permissions.openSettings(pane) }
        }
    }

    private func saveKey(_ key: String) {
        do {
            try KeychainStore.saveAPIKey(key)
            hasAPIKey = KeychainStore.readAPIKey() != nil
            keyMessage = hasAPIKey ? "保存しました" : "削除しました"
        } catch {
            keyMessage = "キーチェーンに保存できませんでした"
        }
        apiKeyDraft = ""
    }

    private func fetchModels() {
        testMessage = ""
        Task {
            do {
                availableModels = try await controller.polisher.listModels()
                if availableModels.isEmpty { testMessage = "モデルが見つかりませんでした" }
            } catch {
                testMessage = Self.describe(error)
            }
        }
    }

    private func runTest() {
        testing = true
        testMessage = ""
        Task {
            let started = Date()
            do {
                let result = try await controller.polisher.polish(
                    raw: "えーと、これは、あのー接続テストです", dictionary: [])
                testMessage = String(format: "成功（%.1f 秒）: %@", Date().timeIntervalSince(started), result)
            } catch {
                testMessage = Self.describe(error)
            }
            testing = false
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            settings.launchAtLogin = enabled
            loginMessage = ""
        } catch {
            loginMessage = "ログイン項目を変更できませんでした: \(error.localizedDescription)"
        }
    }

    static func describe(_ error: Error) -> String {
        switch error as? PolishError {
        case .missingAPIKey: return "API キーが保存されていません"
        case .timeout: return "時間内に応答がありませんでした"
        case .http(status: 401): return "API キーが正しくありません"
        case .http(status: 404): return "このモデル ID は使えません"
        case .http(status: 429): return "利用上限に達しています"
        case .http(let status): return "エラー（HTTP \(status)）"
        case .badResponse: return "応答を解釈できませんでした"
        case nil: return "通信できませんでした"
        }
    }
}
