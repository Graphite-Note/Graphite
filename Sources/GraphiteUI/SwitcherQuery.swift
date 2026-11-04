/**
 * File: SwitcherQuery.swift
 * -------------------------
 * Layer: UI
 * Description: What the quick switcher's field says: the file to find, a heading or block to jump to, and the folder and name of a new note.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import Foundation
import GraphiteCore

/// The quick switcher's field read as Obsidian reads it: `Note#Heading` and `Note#^block` go to a
/// place in a note, and `Folder/New note` makes a note in a folder.
struct SwitcherQuery: Equatable {
    /// The words the files are found by: the field without the place in the note.
    let noteQuery: String
    /// The place in the note, `Heading` or `^block`; nil when the field names only a file.
    let fragment: String?
    /// The folder a new note goes in, or nil for the vault's usual place for new notes.
    let folder: VaultPath?
    /// The name a new note gets.
    let newName: String

    init(_ text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespaces)
        var notePart = trimmedText
        var fragment: String?
        if let separator = trimmedText.firstIndex(where: { character in character == "#" || character == "^" }), separator != trimmedText.startIndex {
            notePart = String(trimmedText[..<separator]).trimmingCharacters(in: .whitespaces)
            let rest = String(trimmedText[separator...])
            // `#^id` is a block as `^id` is; `#Heading` is a heading.
            let place = rest.hasPrefix("#") ? String(rest.dropFirst()) : rest
            fragment = place.isEmpty ? nil : place
        }
        noteQuery = notePart
        self.fragment = fragment
        if let slash = notePart.lastIndex(of: "/") {
            let folderText = String(notePart[..<slash])
            folder = folderText.isEmpty ? nil : (try? VaultPath(folderText)) // Typed text; not a path: no folder, and the reason is given.
            newName = String(notePart[notePart.index(after: slash)...]).trimmingCharacters(in: .whitespaces)
        } else {
            folder = nil
            newName = notePart
        }
    }

    /// Why no note is created from the field, or nil when one can be.
    var creationProblem: String? {
        if fragment != nil { return "A note is created from a name; “#” and “^” go to a place in a note that exists." }
        if newName.isEmpty { return nil }
        if noteQuery.contains("/"), folder == nil { return "The folder name is not valid." }
        return FileNameRules.problem(with: newName, isNote: true)
    }

    /// The target a match is followed to for the place in the note, written as a link is.
    func linkTarget(to path: VaultPath) -> String? {
        fragment.map { place in path.rawValue + "#" + place }
    }
}
