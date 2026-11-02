/**
 * File: BaseViewEditing.swift
 * ---------------------------
 * Layer: UI
 * Description: The view editor's draft of one view of a base, and the view it was made from, followed as the file
 *              changes.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import GraphiteCore

/// The view editor's draft and the view it was made from. The base can be loaded again
/// while the sheet is open, after an edit in another app. Saving writes the fields that
/// differ from `original`, so a draft kept across such a change would revert it, or be
/// written over another view that moved into its place.
struct BaseViewEditing: Equatable {
    enum FileChange: Equatable {
        case viewChanged, viewRemoved
    }

    var draft: BaseViewDraft
    private(set) var original: BaseViewDraft
    /// The view's position in the file's `views` list (`BaseView.id`) when the draft was made.
    private(set) var viewPosition: Int
    /// Set when the file changed under an edited draft, which can then not be saved.
    private(set) var fileChange: FileChange?

    init(view: BaseView) {
        let viewDraft = BaseViewDraft(view: view)
        draft = viewDraft
        original = viewDraft
        viewPosition = view.id
    }

    /// Marked as removed when the definition has no view at `viewIndex`, which can
    /// happen when the base was loaded again just before the sheet opened.
    init(viewAt viewIndex: Int, in definition: BaseDefinition) {
        guard definition.views.indices.contains(viewIndex) else {
            self.init(view: BaseView(id: viewIndex, type: .table, name: ""))
            fileChange = .viewRemoved
            return
        }
        self.init(view: definition.views[viewIndex])
    }

    var hasChanges: Bool { draft != original }

    /// Follows the file after it was loaded again. A draft without changes starts over
    /// from the view as it is now; an edited one is kept but marked as out of date.
    mutating func fileLoaded(_ view: BaseView?) {
        guard let view else {
            fileChange = .viewRemoved
            return
        }
        if view.id == viewPosition && BaseViewDraft(view: view) == original {
            fileChange = nil
        } else if hasChanges {
            fileChange = .viewChanged
        } else {
            self = BaseViewEditing(view: view)
        }
    }

    /// Drops the changes and edits the view as the file has it now.
    mutating func discardChanges(reloading view: BaseView) {
        self = BaseViewEditing(view: view)
    }
}
