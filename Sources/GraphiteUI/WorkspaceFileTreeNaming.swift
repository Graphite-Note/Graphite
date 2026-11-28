/**
 * File: WorkspaceFileTreeNaming.swift
 * -----------------------------------
 * Layer: UI
 * Description: Where a rename or a new item is named: in the file tree's row when the tree is on screen, as in
 *              VSCodium's explorer, else in its sheet; and what a finished name field does.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 27/11/2026
 */

import Foundation
import GraphiteCore

extension WorkspaceModel {
    /// The tree on screen names its rows; one tree per window, so the last to appear wins and only it can leave.
    func registerFileTreeNaming(_ naming: any FileTreeNaming) {
        fileTreeNaming = naming
    }

    func unregisterFileTreeNaming(_ naming: any FileTreeNaming) {
        guard fileTreeNaming === naming else { return }
        fileTreeNaming = nil
    }

    /// Renames in the item's row of the file tree, or in the Rename sheet when the tree does not show it.
    func requestRename(_ path: VaultPath) {
        if fileTreeNaming?.beginNaming(.rename(path)) == true { return }
        fileSheet = .rename(path)
    }

    /// Names a new folder in a row of the file tree, inside `directory`, or in the New Folder sheet.
    func requestNewFolder(in directory: VaultPath) {
        if fileTreeNaming?.beginNaming(.create(.folder, in: directory)) == true { return }
        fileSheet = .newFolder(in: directory)
    }

    /// Starts naming a new note, base or canvas in a row of the file tree, in `directory` or the vault's folder for new
    /// notes; false when the tree cannot (a notebook, or no tree on screen), and the caller shows its sheet.
    func beginNamingInFileTree(_ kind: CreationKind, in directory: VaultPath?) -> Bool {
        guard let creatableKind = FileTreeCreatableKind(kind), let fileTreeNaming else { return false }
        return fileTreeNaming.beginNaming(.create(creatableKind, in: newFileDirectory(directory)))
    }

    /// The creation a sheet still has to ask for: nil when the file tree names the new note, base, canvas or folder in
    /// a row, as VSCodium's explorer does; the request itself from the library (which opens it in a tab of its own), for
    /// a notebook or a course, or while no tree is on screen.
    func creationSheet(for request: CreationRequest) -> CreationRequest? {
        if !request.opensInNewTab, beginNamingInFileTree(request.kind, in: request.directory) { return nil }
        return request
    }

    /// The sheet for a new item of `kind` in `directory` (nil: the vault's folder for new notes), or nil when the file
    /// tree names it in a row.
    func creationSheet(_ kind: CreationKind, in directory: VaultPath? = nil) -> CreationRequest? {
        creationSheet(for: CreationRequest(kind: kind, directory: directory))
    }

    /// Does what a finished name field asked for. `opensCreatedItem` false makes a new item without opening it: the
    /// field was left by a click on another row, which opens that row's item.
    func finishNaming(_ outcome: FileTreeNamingOutcome, opensCreatedItem: Bool = true) async {
        switch outcome {
        case .cancel: return
        case .rename(let path, let newName): await rename(path, to: newName)
        case .create(let kind, let name, let directory):
            switch kind {
            case .note: await createNote(named: name, in: directory, opens: opensCreatedItem)
            case .base: await createBase(named: name, in: directory, opens: opensCreatedItem)
            case .canvas: await createCanvas(named: name, in: directory, opens: opensCreatedItem)
            case .folder: await createFolder(named: name, in: directory)
            }
        }
    }
}
