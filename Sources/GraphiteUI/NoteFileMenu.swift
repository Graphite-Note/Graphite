import SwiftUI
import GraphiteCore

/// The note's own file commands in one submenu of its More menu: where it is (a link to it, Show in Files),
/// exporting it to PDF, its saved versions, moving it and deleting it. The menu ran to 25 entries, cut off at
/// about 520 points of a phone's screen, and had neither Move nor Delete (HUNT-277).
struct NoteFileMenu: View {
    @Bindable var workspace: WorkspaceModel
    let path: VaultPath

    var body: some View {
        Menu("File", systemImage: "doc") {
            FileLocationMenuItems(path: path, openingLink: workspace.openingLink(to: path), vaultRoot: workspace.folderAccess?.root)
            NotePDFExportButton()
            if workspace.preferences.isEnabled(.fileRecovery) {
                Button("File Recovery…", systemImage: "clock.arrow.circlepath") { workspace.fileRecoveryRequest = FileRecoveryRequest(path: path) }
            }
            Divider()
            Button("Move to…", systemImage: VaultEntryAction.moveTo.systemImage) { workspace.perform(.moveTo, on: path) }
            Button("Delete", systemImage: VaultEntryAction.delete.systemImage, role: .destructive) { workspace.perform(.delete, on: path) }
        }
    }
}
