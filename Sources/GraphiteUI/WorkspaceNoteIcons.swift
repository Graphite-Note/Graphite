/**
 * File: WorkspaceNoteIcons.swift
 * ------------------------------
 * Layer: UI
 * Description: Where a window's note icons are read from: the open vault's index, with the key that changes when the
 *              vault does, its index arrives or the index's properties change.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 28/11/2026
 */

import Foundation

extension WorkspaceModel {
    /// The index the window's `NoteIconCatalog` reads, and when to read it again (`PageLookLayer`): another vault, the
    /// vault's index arriving, or a change of its properties. The index arrives after the vault's identity, and a vault
    /// unchanged since its last scan changes no property, so without the index in the key the one read made before it
    /// arrived found no index and no note's icon showed outside its own page.
    var noteIconSource: NoteIconSource {
        let indexKey = index.map { vaultIndex in String(describing: ObjectIdentifier(vaultIndex)) } ?? "none"
        return NoteIconSource(index: index, root: folderAccess?.root,
                              reloadKey: "\(currentVaultIdentifier?.uuidString ?? "")|\(indexKey)|\(structureVersion)")
    }
}
