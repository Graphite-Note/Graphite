/**
 * File: QuickSwitcherCreation.swift
 * ---------------------------------
 * Layer: UI
 * Description: The quick switcher's row that creates the note its field names, or says why none can be created.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import SwiftUI
import GraphiteCore

extension QuickSwitcher {
    /// The row that creates the note the field names, or says why none can be created.
    func creationItem(for switcher: SwitcherQuery) -> PaletteItem {
        if let problem = switcher.creationProblem {
            var explanation = PaletteItem(id: "create-refused", title: "Can’t create “\(switcher.noteQuery)”", subtitle: problem,
                                          systemImage: "exclamationmark.circle") {}
            explanation.requiresExplicitChoice = true
            return explanation
        }
        // Until the index has seen every file, a note may exist without being found:
        // Return then does not create a second one.
        let isIndexComplete = workspace.isIndexUsable
        let directory = workspace.newFileDirectory(switcher.folder)
        let directoryDescription = directory.rawValue.isEmpty ? workspace.title : directory.rawValue
        var create = PaletteItem(id: "create", title: "Create “\(switcher.newName)”",
                                 subtitle: isIndexComplete ? "New note in \(directoryDescription)"
                                                           : "Graphite is still reading the vault; this note may already exist",
                                 systemImage: "plus") { [workspace] in
            Task { await workspace.createNote(named: switcher.newName, in: switcher.folder) }
        }
        create.requiresExplicitChoice = !isIndexComplete
        return create
    }
}
