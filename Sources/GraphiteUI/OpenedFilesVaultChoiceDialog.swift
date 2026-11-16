/**
 * File: OpenedFilesVaultChoiceDialog.swift
 * ----------------------------------------
 * Layer: UI
 * Description: Asks which vault files opened from another app go into, when none is open and several are known.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 13/11/2026
 */

import SwiftUI
import GraphiteCore

/// Asks which vault the files opened in Graphite from another app go into, while no vault is open and several are
/// known (`WorkspaceModel.openedFilesAwaitingVault`): one button per vault, the most recently opened first, and Cancel,
/// which removes the copies. The answer is handed to `choose` with the files it answers for, so it holds even when
/// the dialog clears its binding before the button's action runs.
struct OpenedFilesVaultChoiceDialog: ViewModifier {
    @Binding var waiting: OpenedFilesAwaitingVault?
    let vaults: [KnownVault]
    let choose: (OpenedFilesAwaitingVault, KnownVault?) -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(waiting.map { files in "Import \(files.description) into which vault?" } ?? "",
                                   isPresented: Binding(get: { waiting != nil }, set: { isPresented in if !isPresented { waiting = nil } }),
                                   titleVisibility: .visible, presenting: waiting) { files in
            ForEach(vaults.sorted { leftVault, rightVault in leftVault.lastOpenedDate > rightVault.lastOpenedDate }) { vault in
                Button(vault.name) { choose(files, vault) }
            }
            Button("Cancel", role: .cancel) { choose(files, nil) }
        } message: { _ in
            Text("No vault is open. The file is copied into the vault's folder for new files; the original is not changed.")
        }
    }
}
