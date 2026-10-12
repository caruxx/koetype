import AppKit
import SwiftUI

struct TranscriptView: View {
    let text: String
    /// Where the transcript was saved; nil when showing an error message instead.
    let file: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView {
                Text(text)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                if let file {
                    Text(file.lastPathComponent).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if let file {
                    Button("Finder で表示") { NSWorkspace.shared.activateFileViewerSelecting([file]) }
                    Button("コピー") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    }
                }
            }
        }
        .padding(14)
        .frame(minWidth: 560, minHeight: 420)
    }
}
