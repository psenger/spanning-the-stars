import SwiftUI
import AppKit

enum SettingsKeys {
    /// Off by default. Read when a game starts, loads or resumes.
    static let diagnosticLogging = "diagnosticLogging"
}

/// The Settings window (Command-comma).
struct SettingsView: View {
    @AppStorage(SettingsKeys.diagnosticLogging) private var diagnosticLogging = false

    var body: some View {
        Form {
            Section {
                Toggle("Diagnostic logging", isOn: $diagnosticLogging)
                    .help("Record moves in future games for troubleshooting")
                    .onChange(of: diagnosticLogging) { InteractionSound.selection.play() }
                Text("Records every move of a game to a replay file, so a problem can be reproduced exactly. "
                     + "Takes effect from the next new, loaded or continued game. The newest 20 files are kept.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                GameButton("Show logs in Finder", help: "Open the diagnostic log folder", action: showLogs)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func showLogs() {
        try? FileManager.default.createDirectory(at: AppFolders.logs, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([AppFolders.logs])
    }
}
