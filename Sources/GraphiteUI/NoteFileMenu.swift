/**
 * File: NoteFileMenu.swift
 * ------------------------
 * Layer: UI
 * Description: The File submenu of a note's More menu: where the file is, export, saved versions, move and delete.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import SwiftUI
import GraphiteCore

/// The note's own file commands in one submenu of its More menu: where it is (a link to it, Show in Files),
/// exporting it to PDF, its saved versions, moving it and deleting it. The menu ran to 25 entries, cut off at
/// about 520 points of a phone's screen, and had neither Move nor Delete (HUNT-277).
struct NoteFileMenu: View {
    let path: VaultPath
    let openingLink: String
    let vaultRoot: URL?
    /// Nil while the File Recovery core plugin is off.
    let showFileRecovery: (() -> Void)?
    let move: () -> Void
    let delete: () -> Void

    var body: some View {
        Menu("File", menuSymbol: "doc") {
            FileLocationMenuItems(path: path, openingLink: openingLink, vaultRoot: vaultRoot)
            NotePDFExportButton()
            if let showFileRecovery {
                Button("File Recovery…", menuSymbol: "clock.arrow.circlepath", action: showFileRecovery)
            }
            Divider()
            Button("Move to…", menuSymbol: VaultEntryAction.moveTo.systemImage, action: move)
            Button("Delete", menuSymbol: VaultEntryAction.delete.systemImage, role: .destructive, action: delete)
        }
    }
}
