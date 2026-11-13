/**
 * File: WorkspaceFileImports.swift
 * --------------------------------
 * Layer: UI
 * Description: Files brought into the vault from outside it, by a drop, the file picker or another app's Open in.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 13/11/2026
 */

import Foundation
import GraphiteCore

extension WorkspaceModel {
    /// Copies files chosen outside the vault into `directory`, each under a free name, as
    /// Goodnotes' Import does. The originals stay where they are. A file or folder an importer
    /// takes goes to it: Goodnotes and Notability notebooks and folders of them to the notebook
    /// import (while its core plugin is on), then the importers of `DroppedFileImporters`; a text
    /// file becomes a note. A file that fails is reported; the others are still copied.
    /// - Parameter stagedCopies: Temporary copies of dropped files that `chosenSources` point into. Each is removed when
    ///   the import is done with it: when its importer returns, at the end of this call, or, for a notebook being
    ///   converted, only when that conversion has ended, since it reads it long after this call returns. The
    ///   conversion's end says nothing about the other files of the drop, which this call may still be copying.
    /// - Parameter importers: Asked after the notebook import and before the plain copy, as `DroppedFileImporters.registered` is.
    /// - Returns: The files the plain copy made; a notebook being converted is not among them.
    @discardableResult
    func importFiles(from chosenSources: [URL], into directory: VaultPath, stagedCopies: DroppedFileBatch? = nil,
                     importers: [FileTypeImporter] = DroppedFileImporters.registered) async -> [VaultPath] {
        var copiesThisCallRemoves = stagedCopies ?? DroppedFileBatch(files: [])
        defer { copiesThisCallRemoves.discard() }
        guard store != nil, folderAccess?.root != nil else { return [] }
        let routing = DroppedFileImporters.route(chosenSources, through: [notebookFileImporter].compactMap(\.self) + importers)
        for routed in routing.routed {
            let copies = copiesThisCallRemoves.split(at: routed.files)
            copiesThisCallRemoves = copies.others
            await routed.importer.importFiles(routed.files, directory, copies.atLocations).discard()
        }
        let copied = await copyIntoVault(routing.remaining, into: directory)
        if !copied.importedPaths.isEmpty {
            refreshIndex(for: copied.importedPaths)
            await refreshDirectory()
        }
        if !copied.failedNames.isEmpty {
            errorMessage = "Could not import " + copied.failedNames.map { name in "“\(name)”" }.joined(separator: ", ") + "."
        }
        return copied.importedPaths
    }

    /// Copies each source into `directory` under a free name, a text file as a note, without refreshing the index or
    /// the file list, which the caller does once for all its copies.
    func copyIntoVault(_ sources: [URL], into directory: VaultPath) async -> (importedPaths: [VaultPath], failedNames: [String]) {
        guard let store, let root = folderAccess?.root else { return ([], sources.map(\.lastPathComponent)) }
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
        return (importedPaths, failedNames)
    }
}
