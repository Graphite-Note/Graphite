/**
 * File: WorkspaceWindowOpening.swift
 * ----------------------------------
 * Layer: UI
 * Description: Opening the vault a window shows, one request after another.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import Foundation
import GraphiteCore

/// Opening the vault a window shows. A window can be asked twice at once, as a new window of
/// the iPad is: to restore the vault used last, and to open the vault of the file dragged out
/// to it. The requests run one after another (`inOrderOfWindowOpening`); two vault openings
/// interleaved on one workspace, and the one that ended last decided which tabs it showed.
extension WorkspaceModel {
    /// Opens the vault used most recently, at launch.
    func restoreVault() async {
        await inOrderOfWindowOpening { [self] in await restoreVaultNow() }
    }

    private func restoreVaultNow() async {
        guard folderAccess == nil, let vault = vaultLibrary.list.mostRecentlyOpened else { return }
        await reopen(vault, tabs: .vaultsLast)
    }

    /// Opens a vault the window was opened on (`GraphiteWindowContent`): with the vault's
    /// remembered tabs, or with one empty tab, or `file`, for a window opened from another.
    func openVaultOfWindow(_ vaultIdentifier: UUID, tabs: WindowTabsToRestore, showing file: VaultPath?) async {
        await inOrderOfWindowOpening { [self] in await openVaultOfWindowNow(vaultIdentifier, tabs: tabs, showing: file) }
    }

    private func openVaultOfWindowNow(_ vaultIdentifier: UUID, tabs: WindowTabsToRestore, showing file: VaultPath?) async {
        guard let vault = vaultLibrary.vault(withIdentifier: vaultIdentifier) else { return await restoreVaultNow() }
        await reopen(vault, tabs: tabs)
        if let file, currentVaultIdentifier == vaultIdentifier { _ = await open(file) }
    }

    /// Runs `opening` once the window's earlier requests to open its vault have ended.
    private func inOrderOfWindowOpening(_ opening: @escaping @MainActor () async -> Void) async {
        let earlierOpening = windowVaultOpening
        let thisOpening = Task { @MainActor in
            await earlierOpening?.value
            await opening()
        }
        windowVaultOpening = thisOpening
        await thisOpening.value
    }
}
