/**
 * File: WorkspaceArchiveImport.swift
 * ----------------------------------
 * Layer: UI
 * Description: A ZIP archive chosen with Import, dropped on the library or the file list, or opened in Graphite from another
 *              app: unpacked into a temporary folder, then its files copied and its notebooks converted into the vault,
 *              its folders kept.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 13/11/2026
 */

import Foundation
import GraphiteCore
import GraphiteApple
import NotebookImport

extension WorkspaceModel {
    /// The importer by file type for ZIP archives (`importFiles(from:into:)`), so an archive chosen with Import, dropped
    /// on the library or the file list, or opened from another app is unpacked the same way: a Goodnotes or Notability
    /// export of several notebooks, or a zipped folder, arrives as its folders, files and converted notebooks rather
    /// than as the ZIP. The unpacking has read the whole archive when `importArchive` returns, so a drop's temporary
    /// copy of it is removed then.
    var archiveFileImporter: FileTypeImporter {
        FileTypeImporter(fileExtensions: [ZipArchiveHandling.fileExtension]) { [weak self] archives, folder in
            for archive in archives { await self?.importArchive(archive, into: folder) }
        }
    }

    /// Imports the contents of the ZIP archive at `archive` into `directory`: it is unpacked into a temporary folder
    /// (`ZipArchiveUnpacking`, which refuses a zip bomb and any name that leaves the folder), laid out as Archive
    /// Utility lays it out (`ArchiveImportLayout`), its files copied as Import copies them, and its Goodnotes and
    /// Notability notebooks converted, while the Notebook Import core plugin is on, by one notebook import whose report
    /// follows. The temporary folder is removed when the last of its files has been read: at once, or when the
    /// conversion ends. The archive itself is only read. What could not be imported is said in one message.
    func importArchive(_ archive: URL, into directory: VaultPath) async {
        let archiveName = archive.lastPathComponent
        let unpackingFolder: URL
        do { unpackingFolder = try DroppedFileStaging.makeStagingFolder() } catch {
            errorMessage = ArchiveImportWording.noUnpackingFolder(archiveName: archiveName)
            return
        }
        let unpacking = await Task.detached(priority: .userInitiated) { () -> Result<UnpackedArchive, ArchiveUnpackingFailure> in
            // An archive chosen with Import is read where it is, outside the app's own folders.
            let hasAccess = archive.startAccessingSecurityScopedResource()
            defer { if hasAccess { archive.stopAccessingSecurityScopedResource() } }
            return Result { () throws(ArchiveUnpackingFailure) in try ZipArchiveUnpacking.unpack(archive, into: unpackingFolder) }
        }.value
        let unpacked: UnpackedArchive
        switch unpacking {
        case .success(let archiveContents): unpacked = archiveContents
        case .failure(let failure):
            DroppedFileStaging.discard([unpackingFolder])
            errorMessage = ArchiveImportWording.failure(failure, archiveName: archiveName)
            return
        }
        let layout = ArchiveImportLayout(unpacked, archiveStem: archive.deletingPathExtension().lastPathComponent)
        guard !layout.files.isEmpty else {
            DroppedFileStaging.discard([unpackingFolder])
            errorMessage = ArchiveImportLayout.isEmptyMessage(unpacked, archiveName: archiveName)
            return
        }
        let failedNames = await place(layout, into: directory, unpackingFolder: unpackingFolder)
        if let leftOut = ArchiveImportWording.leftOut(unpacked.leftOutEntries, notCopied: failedNames, archiveName: archiveName) {
            errorMessage = [errorMessage, leftOut].compactMap(\.self).joined(separator: "\n\n")
        }
    }

    /// Copies the layout's files into the vault and hands its notebooks to the notebook import; returns the names of the
    /// files that were not copied. The unpacking folder is removed once nothing reads it any more.
    private func place(_ layout: ArchiveImportLayout, into directory: VaultPath, unpackingFolder: URL) async -> [String] {
        let unpackedFiles = DroppedFileBatch(files: layout.files.map { file in DroppedFile(location: file.location, stagingFolder: unpackingFolder) })
        guard let folderName = layout.folderName else {
            // One file alone, imported as Import imports it: it reports a failure itself, and keeps a notebook's copy
            // until its conversion ends. A ZIP inside the ZIP is copied as it is: unpacking it too would never end for
            // an archive that holds itself.
            await importFiles(from: unpackedFiles.locations, into: directory, stagedCopies: unpackedFiles, zipArchives: .copiedAsTheyAre)
            return []
        }
        guard let archiveFolder = await newFolder(named: folderName, in: directory) else {
            unpackedFiles.discard()
            return layout.files.map(\.location.lastPathComponent)
        }
        let convertsNotebooks = notebookFileImporter != nil
        let isConvertedNotebook = { (file: ArchiveImportLayout.PlacedFile) in
            convertsNotebooks && NotebookFileFormat(fileExtension: file.location.pathExtension) != nil
        }
        var importedPaths: [VaultPath] = []
        var failedNames: [String] = []
        for group in layout.filesByFolder {
            let copiedFiles = group.files.filter { file in !isConvertedNotebook(file) }
            guard !copiedFiles.isEmpty else { continue }
            let folderPath = group.folderNames.joined(separator: "/")
            guard let folder = folderPath.isEmpty ? archiveFolder : try? archiveFolder.appending(folderPath) else { // No vault path holds it.
                failedNames += copiedFiles.map(\.location.lastPathComponent)
                continue
            }
            let copied = await copyIntoVault(copiedFiles.map(\.location), into: folder)
            importedPaths += copied.importedPaths
            failedNames += copied.failedNames
        }
        refreshIndex(for: importedPaths)
        await refreshDirectory()
        let hasNotebooks = layout.files.contains(where: isConvertedNotebook)
        let convertsLater = hasNotebooks && importNotebooks([layout.contentsFolder], into: archiveFolder, folderPlacement: .intoDestination,
                                                            whenEnded: { unpackedFiles.discard() })
        if !convertsLater { unpackedFiles.discard() }
        return failedNames
    }

    /// A new folder of a free name based on `name` in `directory`, made now; nil when the vault refuses it.
    private func newFolder(named name: String, in directory: VaultPath) async -> VaultPath? {
        guard let store else { return nil }
        do {
            let folder = try await store.uniquePath(directory: directory, stem: name, extension: "")
            try await store.createDirectory(folder)
            return folder
        } catch {
            return nil
        }
    }
}

extension ArchiveImportLayout {
    /// Why an archive whose unpacking left no file imports nothing: it was empty, or every entry was left out.
    static func isEmptyMessage(_ unpacked: UnpackedArchive, archiveName: String) -> String {
        ArchiveImportWording.leftOut(unpacked.leftOutEntries, notCopied: [], archiveName: archiveName)
            ?? ArchiveImportWording.holdsNothing(archiveName: archiveName)
    }
}

/// What `WorkspaceModel.importFiles(from:into:)` does with a ZIP archive.
enum ZipArchiveHandling {
    /// Unpacked and its contents imported: what Import, a drop and a file opened from another app do.
    case unpacked
    /// Copied as the file it is: a ZIP found inside an archive that is being unpacked.
    case copiedAsTheyAre

    /// The extension of the archives unpacked, lowercased as `FileTypeImporter` compares them.
    static let fileExtension = "zip"

    var unpacksArchives: Bool {
        switch self {
        case .unpacked: true
        case .copiedAsTheyAre: false
        }
    }
}
