/**
 * File: WorkspaceFileImports.swift
 * --------------------------------
 * Layer: UI
 * Description: Files brought into the vault from outside it, by a drop or the file picker.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 02/11/2026
 */

import Foundation
import GraphiteCore

extension WorkspaceModel {
    /// Copies files chosen outside the vault into `directory`, each under a free name, as
    /// Goodnotes' Import does. The originals stay where they are. A file of a type an importer
    /// of `DroppedFileImporters` takes goes to it; a text file becomes a note. A file that fails
    /// is reported; the others are still copied.
    /// - Parameter stagedCopies: Temporary copies of dropped files that `chosenSources` point into. Each is removed when
    ///   the import is done with it: at the end of this call, or, for a notebook being converted, only when that
    ///   conversion has ended, since it reads it long after this call returns. The conversion's end says nothing about
    ///   the other files of the drop, which this call may still be copying.
    /// - Parameter importers: Asked before the plain copy, as `DroppedFileImporters.registered` is.
    func importFiles(from chosenSources: [URL], into directory: VaultPath, stagedCopies: DroppedFileBatch? = nil,
                     importers: [FileTypeImporter] = DroppedFileImporters.registered) async {
        var copiesThisCallRemoves = stagedCopies
        defer { copiesThisCallRemoves?.discard() }
        guard let store, let root = folderAccess?.root else { return }
        // Goodnotes and Notability notebooks, and folders of them, are converted rather than copied.
        let notebookSources = notebookImportSources(in: chosenSources)
        copiesThisCallRemoves = startNotebookImport(of: notebookSources, into: directory, stagedCopies: stagedCopies)
        let routing = DroppedFileImporters.route(chosenSources.filter { source in !notebookSources.contains(source) },
                                                 through: importers)
        for routed in routing.routed { await routed.importer.importFiles(routed.files, directory) }
        let sources = routing.remaining
        var importedPaths: [VaultPath] = []
        var failedNames: [String] = []
        for source in sources {
            let hasAccess = source.startAccessingSecurityScopedResource()
            defer { if hasAccess { source.stopAccessingSecurityScopedResource() } }
            do {
                try await store.createDirectory(directory)
                let stem = source.deletingPathExtension().lastPathComponent
                let fileExtension = ImportedFileName.fileExtension(forSourceExtension: source.pathExtension)
                let path = try await store.uniquePath(directory: directory, stem: stem, extension: fileExtension)
                let destination = try path.url(in: root)
                let writer = store.writer
                _ = try await Task.detached { try writer.copy(from: source, to: destination, expecting: .absent) }.value
                importedPaths.append(path)
            } catch {
                failedNames.append(source.lastPathComponent)
            }
        }
        if !importedPaths.isEmpty {
            refreshIndex(for: importedPaths)
            await refreshDirectory()
        }
        if !failedNames.isEmpty {
            errorMessage = "Could not import " + failedNames.map { name in "“\(name)”" }.joined(separator: ", ") + "."
        }
    }

    /// Hands notebooks to an import, which removes their copies when it ends. Returns the copies its caller still removes:
    /// the others, or all of them when no import started.
    private func startNotebookImport(of notebookSources: [URL], into directory: VaultPath, stagedCopies: DroppedFileBatch?) -> DroppedFileBatch? {
        guard !notebookSources.isEmpty else { return stagedCopies }
        let copies = stagedCopies?.split(at: notebookSources)
        return importNotebooks(notebookSources, into: directory, whenEnded: { copies?.atLocations.discard() }) ? copies?.others : stagedCopies
    }
}
