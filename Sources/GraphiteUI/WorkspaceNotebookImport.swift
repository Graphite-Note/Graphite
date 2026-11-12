/**
 * File: WorkspaceNotebookImport.swift
 * -----------------------------------
 * Layer: UI
 * Description: Hands the Goodnotes and Notability notebooks of an import to a notebook import session.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 12/11/2026
 */

import Foundation
import GraphiteCore
import GraphiteApple
import NotebookImport

/// Importing Goodnotes and Notability notebooks: the New menu's Import, the library's, and files dropped on the library
/// or the file list all reach `importFiles(from:into:)`, whose importers by file type hand the notebooks and folders to
/// this (`notebookFileImporter`). The share
/// sheet will too, once the share extension delivers its files into the vault through the same call.
extension WorkspaceModel {
    /// The notebook import as one of the importers by file type, while the Notebook Import core plugin is on: it takes
    /// Goodnotes and Notability files and folders, such as a library export, whose notebooks are converted and whose
    /// folders are kept. It keeps the temporary copies of a drop until the conversion that reads them has ended; when no
    /// import starts (one is already running) it hands them back. Off, it is not there and a notebook is copied as the file
    /// it is.
    var notebookFileImporter: FileTypeImporter? {
        guard preferences.isEnabled(.notebookImport) else { return nil }
        let notebookExtensions = Set(NotebookFileFormat.allCases.map(\.fileExtension))
        return FileTypeImporter(fileExtensions: notebookExtensions, takesFolders: true) { [weak self] sources, folder, copies in
            guard let self, self.importNotebooks(sources, into: folder, whenEnded: { copies.discard() }) else { return copies }
            return DroppedFileBatch(files: [])
        }
    }

    /// Converts the notebooks of `sources` into `directory`, away from the main actor, while the vault stays usable; the
    /// progress shows over the document area and a report follows (`NotebookImportPresentation`). One import runs at a
    /// time: while one runs, the person is told to wait.
    /// - Parameter whenEnded: Called when the import has ended, and only then; see `NotebookImportSession`.
    /// - Returns: Whether an import started, and so will call `whenEnded`; when it did not, the caller still owns whatever
    ///   `whenEnded` would have released.
    @discardableResult
    func importNotebooks(_ sources: [URL], into directory: VaultPath, whenEnded: @escaping @Sendable () -> Void = {}) -> Bool {
        guard let store, let root = folderAccess?.root else { return false }
        guard notebookImport == nil else {
            errorMessage = "Notebooks are already being imported. Import these when that import has finished."
            return false
        }
        // The one read of the wall clock for an import: every imported stroke is dated when the import began.
        let run = NotebookImportRun(vault: notebookImportVault(store: store, root: root), conversion: NotebookConversion(fileWriter: store.writer),
                                    limits: .standard, strokeCreationDate: .now)
        notebookImport = NotebookImportSession(sources: sources, destination: directory, run: run, whenEnded: whenEnded)
        return true
    }

    /// Lets the import go once its report is closed, so nothing of it stays.
    func endNotebookImport() {
        notebookImport?.stopImportAndObservation()
        notebookImport = nil
    }

    private func notebookImportVault(store: VaultStore, root: URL) -> NotebookImportVault {
        NotebookImportVault(freePath: { folder, stem, fileExtension in try await store.uniquePath(directory: folder, stem: stem, extension: fileExtension) },
                            makeFolder: { folder in try await store.createDirectory(folder) },
                            location: { path in try path.url(in: root) },
                            fileWriter: store.writer,
                            filesDidChange: { [weak self] paths in
                                self?.refreshIndex(for: paths)
                                await self?.refreshDirectory()
                            })
    }
}
