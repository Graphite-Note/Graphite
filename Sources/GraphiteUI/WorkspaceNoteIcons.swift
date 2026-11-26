/**
 * File: WorkspaceNoteIcons.swift
 * ------------------------------
 * Layer: UI
 * Description: Where a window's note icons are read from: the open vault's index, with the key that changes when the
 *              vault does or the index's properties do.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import Foundation

extension WorkspaceModel {
    /// The index the window's `NoteIconCatalog` reads, and when to read it again (`PageLookLayer`).
    var noteIconSource: NoteIconSource {
        NoteIconSource(index: index, reloadKey: "\(currentVaultIdentifier?.uuidString ?? "")|\(structureVersion)")
    }
}
