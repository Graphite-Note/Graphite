/**
 * File: BaseNoteServices.swift
 * ----------------------------
 * Layer: UI
 * Description: What a base needs from the open vault to link notes in a relation and to make new notes from a view.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import Foundation
import GraphiteCore

/// What a base needs from the open vault to link notes and make new ones: the vault's link format, its search, the
/// Templates settings, its location for new notes, its property types and a new tab. The workspace builds one while
/// Bases are on (`WorkspaceModel.baseNoteServices`); a base without it offers neither the relation picker nor New.
public struct BaseNoteServices {
    /// The link target that names `path` from `note` in the vault's link format, without brackets.
    let linkTarget: @MainActor (_ path: VaultPath, _ note: VaultPath) async -> String
    /// The notes the typed text finds, as the quick switcher finds them, at most `limit`.
    let searchNotes: @MainActor (_ query: String, _ limit: Int) async -> [VaultPath]
    /// A template's text with `{{title}}`, `{{date}}` and `{{time}}` filled in for a note named `title`, as Insert
    /// Template fills them.
    let fillTemplate: @MainActor (_ templateText: String, _ title: String) -> String
    /// Obsidian's "Default location for new notes".
    let newNoteLocation: NewNoteLocation
    /// The types of the vault's properties, declared in `.obsidian/types.json` or taken from its notes.
    let vaultPropertyTypes: @MainActor () async -> [String: PropertyType]
    /// Shows a note New made: in a new tab, in the file list, and in the index.
    let showNewNote: @MainActor (VaultPath) -> Void
}

extension BaseNoteServices {
    /// Whether the vault takes the property as a list, as Obsidian's New asks before it writes one value of it.
    static func isList(_ type: PropertyType?) -> Bool {
        switch type {
        case .multitext?, .tags?, .aliases?: true
        case .text?, .number?, .checkbox?, .date?, .datetime?, nil: false
        }
    }
}
