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
    @State private var showAdvanced = false
    @State private var monthlyUsage = AppController.shared.usage.month(containing: Date())

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                Picker("ホットキー", selection: $settings.hotkey) {
                    ForEach(HotkeyChoice.allCases) { Text($0.label).tag($0) }
                }
                .onChange(of: settings.hotkey) { controller.reloadHotkey() }
            } footer: {
                Text("押している間だけ録音。素早く 2 回押すとハンズフリー、Esc で取り消し。")
                    .footnoteStyle()
            }

            Section {
                Toggle("AI で高精度に整える", isOn: $settings.polishEnabled)
                // Everything about the AI connection stays hidden until it is switched on.
                if settings.polishEnabled {
                    Picker("接続方法", selection: $settings.polishViaCodex) {
                        Text("OpenAI API（速い・従量課金）").tag(false)
                        Text("Codex CLI（ChatGPT の利用枠・約 5 秒）").tag(true)
                    }
                    if !settings.polishViaCodex {
                        HStack {
                            SecureField(hasAPIKey ? "API キー（保存済み）" : "OpenAI の API キー", text: $apiKeyDraft)
                            Button("保存") { saveKey(apiKeyDraft) }
                                .disabled(apiKeyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                            if hasAPIKey { Button("削除") { saveKey("") } }
                        }
                    }
                    HStack {
                        Button("接続テスト") { runTest() }.disabled(testing)
                        if testing { ProgressView().controlSize(.small) }
                        Text(testMessage.isEmpty ? keyMessage : testMessage)
                            .font(.caption).foregroundStyle(.secondary)
                            .lineLimit(2).textSelection(.enabled)
                    }
                    if !settings.polishViaCodex { LabeledContent("今月の利用", value: usageText) }
                }
            } header: {
                Text("整形")
            } footer: {
                Text(settings.polishEnabled
                     ? (settings.polishViaCodex
                        ? "ChatGPT にログイン済みの Codex CLI を通して整えます。API の課金はありませんが、1 回あたり約 5 秒かかり、ChatGPT の利用枠を消費します。"
                        : "言い直しの整理、文脈からの誤認識の修正、辞書どおりの表記統一を OpenAI の Luna で行います。利用した分だけ課金されます。")
                     : "オフの間は Mac の中だけで処理します（無料）。句読点と「えーと」などの除去は行います。精度を上げたいときにオンにすると、OpenAI の Luna に接続できます。")
                    .footnoteStyle()
            }

            Section {
                Toggle("ログイン時に起動", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { setLaunchAtLogin($0) }))
                if !loginMessage.isEmpty {
                    Text(loginMessage).font(.caption).foregroundStyle(.red)
                }
                // Permissions take space only while something still needs the user's attention.
                if controller.microphoneGranted && accessibilityGranted {
                    LabeledContent("権限", value: "許可済み")
                } else {
                    if !controller.microphoneGranted { permissionRow("マイク", pane: .microphone) }
                    if !accessibilityGranted { permissionRow("アクセシビリティ", pane: .accessibility) }
                }
            }

            Section {
                DisclosureGroup("詳細設定", isExpanded: $showAdvanced) {
                    Stepper(value: $settings.minimumAICharacters, in: 0...200, step: 5) {
                        LabeledContent("AI に送る最小の長さ", value: "\(settings.minimumAICharacters) 文字")
                    }
                    .disabled(!settings.polishEnabled)
                    HStack {
                        TextField("整形モデル", text: $settings.polishModel)
                        if availableModels.isEmpty {
                            Button("一覧を取得") { fetchModels() }
                        } else {
                            Picker("", selection: $settings.polishModel) {
                                ForEach(availableModels, id: \.self) { Text($0).tag($0) }
                            }
                            .labelsHidden().frame(width: 170)
                        }
                    }
                    TextField("Codex のモデル", text: $settings.codexModel)
                    TextField("音声認識モデル", text: $whisperModelDraft)
                    HStack {
                        Button("適用") {
                            settings.whisperModel = whisperModelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                            controller.reloadModel()
                        }
                        Button("既定に戻す") {
                            whisperModelDraft = AppSettings.defaultWhisperModel
                            settings.whisperModel = AppSettings.defaultWhisperModel
                            settings.polishModel = AppSettings.defaultPolishModel
                            settings.minimumAICharacters = AppSettings.defaultMinimumAICharacters
                            settings.codexModel = AppSettings.defaultCodexModel
                            controller.reloadModel()
                        }
                        Spacer()
                        Text(modelStateText).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, minHeight: 380)
        .onReceive(timer) { _ in
            accessibilityGranted = Permissions.accessibilityGranted
            controller.refreshPermissions()
        }
        .onReceive(NotificationCenter.default.publisher(for: UsageStore.didChange)
            .receive(on: DispatchQueue.main)) { _ in
            monthlyUsage = controller.usage.month(containing: Date())
        }
    }

    /// Request count and a cost estimate at the default model's list price.
    private var usageText: String {
        let yen = monthlyUsage.estimatedYen(
            inputDollarsPerMillion: AppSettings.estimateInputDollarsPerMillion,
            outputDollarsPerMillion: AppSettings.estimateOutputDollarsPerMillion,
            yenPerDollar: AppSettings.estimateYenPerDollar)
        return String(format: "%d 回・約 %.0f 円（目安）", monthlyUsage.requests, yen)
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

    private func permissionRow(_ name: String, pane: Permissions.Pane) -> some View {
        HStack {
            Text(name)
            Spacer()
            Text("未許可").foregroundStyle(.red)
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
                let result = try await controller.activePolisher.polish(
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

private extension Text {
    /// Section footers read as left-aligned notes under the group they explain.
    func footnoteStyle() -> some View {
        self.multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
