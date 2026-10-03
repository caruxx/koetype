import AppKit
import SwiftUI
import KoeTypeCore

/// Lets the user decide how dictated text should read in each app.
struct AppStylesView: View {
    @ObservedObject private var settings = AppSettings.shared

    private var rules: AppStyleRules { AppStyleRules(overrides: settings.appStyleOverrides) }

    private var rows: [(bundleID: String, style: PolishStyle)] {
        rules.all
            // Built-in rules for apps that are not on this Mac would only be clutter.
            .filter { settings.appStyleOverrides[$0.key] != nil
                || NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.key) != nil }
            .map { (bundleID: $0.key, style: $0.value) }
            .sorted { Self.name(for: $0.bundleID).localizedCompare(Self.name(for: $1.bundleID)) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("文章を入力する先のアプリに合わせて、整え方を変えます。一覧にないアプリは「標準」です。")
                .font(.caption).foregroundStyle(.secondary)
            List(rows, id: \.bundleID) { row in
                HStack(spacing: 10) {
                    Self.icon(for: row.bundleID)
                    Text(Self.name(for: row.bundleID))
                    Spacer()
                    Picker("", selection: binding(for: row.bundleID)) {
                        ForEach(PolishStyle.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .labelsHidden().frame(width: 190)
                }
            }
            HStack {
                Menu("実行中のアプリから追加") {
                    ForEach(runningApps, id: \.bundleID) { app in
                        Button {
                            settings.appStyleOverrides[app.bundleID] = .standard
                        } label: {
                            Label { Text(app.name) } icon: { Self.icon(for: app.bundleID) }
                        }
                    }
                }
                .frame(width: 210)
                Spacer()
                Button("初期設定に戻す") { settings.appStyleOverrides = [:] }
                    .disabled(settings.appStyleOverrides.isEmpty)
            }
        }
        .padding(14)
        .frame(minWidth: 480, minHeight: 420)
    }

    private func binding(for bundleID: String) -> Binding<PolishStyle> {
        Binding(get: { rules.style(forBundleID: bundleID) },
                set: { settings.appStyleOverrides[bundleID] = $0 })
    }

    /// Apps with a Dock icon that are not listed yet.
    private var runningApps: [(bundleID: String, name: String)] {
        let listed = Set(rules.all.keys)
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let bundleID = app.bundleIdentifier, !listed.contains(bundleID) else { return nil }
                return (bundleID: bundleID, name: app.localizedName ?? bundleID)
            }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    /// The app's own icon, so it can be recognised at a glance.
    static func icon(for bundleID: String) -> some View {
        Group {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
            } else {
                Image(systemName: "app.dashed").resizable().foregroundStyle(.secondary)
            }
        }
        .frame(width: 22, height: 22)
    }

    /// The app's display name when it is installed, otherwise its identifier.
    static func name(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}
