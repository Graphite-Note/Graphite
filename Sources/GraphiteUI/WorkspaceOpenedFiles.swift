/**
 * File: WorkspaceOpenedFiles.swift
 * --------------------------------
 * Layer: UI
 * Description: Files opened in Graphite from another app (Open in, Files, AirDrop, the Finder's Open With, the Dock):
 *              copied at once, then imported into the open vault, or into the vault the person chooses.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 13/11/2026
 */

import Foundation
import GraphiteCore
import GraphiteApple

/// Files opened in Graphite while no vault was open and several are known: they wait, copied, for the person to
/// choose the vault they go into (`OpenedFilesVaultChoiceDialog`). One object, so a file opened while the question is
/// on screen joins the files the shown question answers for, and the question is answered once.
@MainActor
final class OpenedFilesAwaitingVault: Identifiable {
    /// The staged copies, removed once imported or when the choice is cancelled.
    fileprivate(set) var files: DroppedFileBatch
    fileprivate var isAnswered = false

    init(files: DroppedFileBatch) {
        self.files = files
    }

    /// The file's name, or how many files there are.
    var description: String { Self.description(of: files) }

    /// The file's name in quotes, or how many files there are.
    static func description(of files: DroppedFileBatch) -> String {
        files.files.count == 1 ? "“\(files.files[0].location.lastPathComponent)”" : "\(files.files.count.formatted()) files"
    }
}

/// A file opened in Graphite from another app arrives as a file URL where a `graphite://` link arrives (`handle(_:)`):
/// the scene's `onOpenURL`, on iOS and on the Mac, queued there until the window's vault has reopened at launch. Graphite
/// imports into its vault rather than editing the file where it is, as Goodnotes' Open in does: the file is copied into
/// a staging folder at once (`OpenedFileStaging`), then imported as Import imports a chosen file, into the vault's
/// folder for new files: a Goodnotes or Notability notebook converted, a ZIP archive unpacked with its folders kept
/// (`importArchive`), any other file copied, a text file as a note. A single file copied is opened.
extension WorkspaceModel {
    func importOpenedFile(_ file: URL) async {
        // Already in the open vault (shared from Graphite's own folder in Files): it is shown, not copied again.
        if let path = vaultPath(for: file) {
            _ = await open(path)
            return
        }
        let inboxFolder = OpenedFileStaging.inboxFolder()
        let staging = await Task.detached(priority: .userInitiated) { Result { try OpenedFileStaging.stage(file, inboxFolder: inboxFolder) } }.value
        guard case .success(let staged) = staging else {
            errorMessage = "Graphite could not read “\(file.lastPathComponent)”, so it was not imported."
            return
        }
        let files = DroppedFileBatch(files: [DroppedFile(location: staged.copy, stagingFolder: staged.folder)])
        if store == nil, await !openVault(forOpenedFiles: files) { return }
        await importStagedOpenedFiles(files)
    }

    /// The person's answer to which vault the waiting files go into; nil cancels, and the copies are removed.
    func importOpenedFiles(_ waiting: OpenedFilesAwaitingVault, into vault: KnownVault?) async {
        if openedFilesAwaitingVault === waiting { openedFilesAwaitingVault = nil }
        guard !waiting.isAnswered else { return }
        waiting.isAnswered = true
        guard let vault else { return waiting.files.discard() }
        guard await open(vault, forOpenedFiles: waiting.files) else { return }
        await importStagedOpenedFiles(waiting.files)
    }

    /// With no vault open: opens the only known vault, or asks which when several are known (and returns false, the
    /// files waiting for the answer); with none, says to make one first.
    private func openVault(forOpenedFiles files: DroppedFileBatch) async -> Bool {
        let knownVaults = vaultLibrary.vaults
        guard knownVaults.count <= 1 else {
            if let waiting = openedFilesAwaitingVault, !waiting.isAnswered {
                waiting.files = DroppedFileBatch(files: waiting.files.files + files.files)
            } else {
                openedFilesAwaitingVault = OpenedFilesAwaitingVault(files: files)
            }
            return false
        }
        guard let vault = knownVaults.first else {
            errorMessage = "Open or create a vault, then open \(OpenedFilesAwaitingVault.description(of: files)) in Graphite again."
            files.discard()
            return false
        }
        return await open(vault, forOpenedFiles: files)
    }

    private func open(_ vault: KnownVault, forOpenedFiles files: DroppedFileBatch) async -> Bool {
        let filesDescription = OpenedFilesAwaitingVault.description(of: files)
        do { try await openVault(vault) } catch {
            errorMessage = "Graphite couldn't open “\(vault.name)”, so \(filesDescription) was not imported. Open the vault and try again."
            files.discard()
            return false
        }
        guard currentVaultIdentifier == vault.id, store != nil else {
            // Another vault was chosen meanwhile: the files go into none rather than into the wrong one.
            errorMessage = "Another vault was chosen while “\(vault.name)” opened, so \(filesDescription) was not imported. Open it again."
            files.discard()
            return false
        }
        return true
    }

    private func importStagedOpenedFiles(_ files: DroppedFileBatch) async {
        let directory = newFileDirectory(nil)
        for file in files.files {
            let staged = DroppedFileBatch(files: [file])
            guard file.location.pathExtension.lowercased() != "zip" else {
                await importArchive(file.location, into: directory)
                staged.discard()
                continue
            }
            let importedPaths = await importFiles(from: [file.location], into: directory, stagedCopies: staged)
            if files.files.count == 1, importedPaths.count == 1 { _ = await open(importedPaths[0]) }
        }
    }
}
