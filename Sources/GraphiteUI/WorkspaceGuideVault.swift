/**
 * File: WorkspaceGuideVault.swift
 * -------------------------------
 * Layer: UI
 * Description: Opening the Graphite Guide vault from the Guide: the reader's copy of the downloaded pack, brought up
 *              to a newer pack first, at a note.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 16/11/2026
 */

import Foundation
import GraphiteCore
import GraphiteApple

extension WorkspaceModel {
    /// `graphite://guide`: opens the reader's copy of the Graphite Guide vault (`GuideVaultCopy`), making it from the
    /// downloaded pack the first time or when `freshCopy` asks, then the note `file` resolves to, or `Start here`. A
    /// copy made from an earlier pack is brought up to this one first (`GuideVaultCopyUpdate`), and the notice says once
    /// what changed. The Guide downloads the pack before it sends the link; without it, the reason is shown and nothing
    /// changes.
    func openGuideVault(at file: String?, freshCopy: Bool) async {
        guard let pack = GuideVaultPack.pack, let packFolder = processServices.addOns.downloadedFolder(of: pack) else {
            errorMessage = "The Graphite Guide vault is not on this device yet. Open it from the Guide, which downloads it first."
            return
        }
        do {
            let copy = GuideVaultCopy(documentsFolder: try VaultLocator.applicationDocumentsFolder(), defaults: deviceDefaults)
            var updateSummary: String?
            let name: String
            if !freshCopy, let existingName = copy.existingCopyName() {
                name = existingName
                if copy.recordedRevision() != pack.revision {
                    updateSummary = try await bringGuideCopyUp(to: pack, from: packFolder, copy: copy, named: name)
                }
            } else {
                name = try copy.makeCopy(of: pack, from: packFolder)
            }
            let vaultFolder = try VaultLocator.applicationDocumentsFolder().appendingPathComponent(name, isDirectory: true)
            if folderAccess?.root.standardizedFileURL != vaultFolder.standardizedFileURL { try await openFolderAsVault(vaultFolder) }
            // A newer choice of vault, made while this one waited its turn, wins.
            guard folderAccess?.root.lastPathComponent == name else { return }
            await openLinkedFile(file ?? GuideVaultPack.startNote)
            if let updateSummary {
                notice = updateSummary
                noticeComesWithSelection = selection
            }
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

    /// Opening another document clears the notice, unless it is the document the notice came with, whose selection
    /// the window sees after the notice was set (the Guide's update, said over the note it opened).
    func clearNoticeOnSelectionChange() {
        if selection == nil || selection != noticeComesWithSelection { notice = nil }
        noticeComesWithSelection = nil
    }

    /// Brings the reader's copy `name` up to `pack` off the main thread, records it, and returns the words that say what
    /// changed, or nil when nothing the reader would notice did.
    private func bringGuideCopyUp(to pack: AddOnPack, from packFolder: URL, copy: GuideVaultCopy, named name: String) async throws -> String? {
        let update = GuideVaultCopyUpdate(packFolder: packFolder, copyFolder: copy.documentsFolder.appendingPathComponent(name, isDirectory: true),
                                          files: pack.files, earlierFiles: GuideVaultPack.earlierFiles, previousFileNames: copy.recordedFileNames())
        let changes = try await Task.detached(priority: .userInitiated) { try update.apply() }.value
        copy.record(pack)
        return GuideVaultUpdateSummary.text(for: changes)
    }
}
