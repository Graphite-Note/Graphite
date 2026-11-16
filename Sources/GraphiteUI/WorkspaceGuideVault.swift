/**
 * File: WorkspaceGuideVault.swift
 * -------------------------------
 * Layer: UI
 * Description: Opening the Graphite Guide vault from the Guide: the reader's copy of the downloaded pack, at a note.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

import Foundation
import GraphiteCore
import GraphiteApple

extension WorkspaceModel {
    /// `graphite://guide`: opens the reader's copy of the Graphite Guide vault (`GuideVaultCopy`), making it from the
    /// downloaded pack the first time or when `freshCopy` asks, then the note `file` resolves to, or `Start here`. The
    /// Guide downloads the pack before it sends the link; without it, the reason is shown and nothing changes.
    func openGuideVault(at file: String?, freshCopy: Bool) async {
        guard let pack = GuideVaultPack.pack, let packFolder = processServices.addOns.downloadedFolder(of: pack) else {
            errorMessage = "The Graphite Guide vault is not on this device yet. Open it from the Guide, which downloads it first."
            return
        }
        do {
            let copy = GuideVaultCopy(documentsFolder: try VaultLocator.applicationDocumentsFolder(), defaults: deviceDefaults)
            let name = try (freshCopy ? nil : copy.existingCopyName()) ?? copy.makeCopy(from: packFolder)
            let vaultFolder = try VaultLocator.applicationDocumentsFolder().appendingPathComponent(name, isDirectory: true)
            if folderAccess?.root.standardizedFileURL != vaultFolder.standardizedFileURL { try await openFolderAsVault(vaultFolder) }
            // A newer choice of vault, made while this one waited its turn, wins.
            guard folderAccess?.root.lastPathComponent == name else { return }
            await openLinkedFile(file ?? GuideVaultPack.startNote)
        } catch let refusal as VaultSwitchRefusal {
            errorMessage = refusal.errorDescription
        } catch let graphiteError as GraphiteError {
            // Such as a recording under way, which keeps the vault that is open.
            errorMessage = graphiteError.errorDescription
        } catch {
            // A copy needs room on the device; opening it, a readable folder in Graphite's own Documents.
            errorMessage = "Graphite could not copy or open the Graphite Guide vault. Check that this device has room, then try again from the Guide."
        }
    }
}
