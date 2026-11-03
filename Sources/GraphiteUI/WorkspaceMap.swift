/**
 * File: WorkspaceMap.swift
 * ------------------------
 * Layer: UI
 * Description: The notes the map places, kept until the vault's files, links or properties change.
 *
 * Authors: Bahey Shalash, Félix Chevalier
 * Version: 0.4
 * Date: 01/11/2026
 */

import Foundation
import GraphiteCore

/// The Map View core plugin.
extension WorkspaceModel {
    /// The notes the map places, read again after a change of the vault's files, links or properties, or the vault's
    /// map plugins name other properties.
    func placedNotes() async -> [PlacedNote]? {
        guard let index, let root = folderAccess?.root else { return nil }
        let version = structureVersion
        let propertyNames = await Task.detached(priority: .userInitiated) { PlacedNote.propertyNames(vaultRoot: root) }.value
        if let placedNotesCache, placedNotesCache.structureVersion == version, placedNotesCache.propertyNames == propertyNames {
            return placedNotesCache.notes
        }
        do {
            let notes = try await index.placedNotes(propertyNames: propertyNames)
            // Notes of a vault left during the query are neither kept nor shown.
            guard self.index === index else { return nil }
            placedNotesCache = (version, propertyNames, notes)
            return notes
        } catch {
            if self.index === index { errorMessage = error.localizedDescription }
            return nil
        }
    }
}
