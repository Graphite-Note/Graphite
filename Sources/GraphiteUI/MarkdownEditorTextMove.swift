/**
 * File: MarkdownEditorTextMove.swift
 * ----------------------------------
 * Layer: UI
 * Description: Text dragged within a note's editor on the iPad and let go elsewhere in the note moves as one step of
 *              the note's history, to the place it was let go.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

#if canImport(UIKit)
import UIKit
import GraphiteCore

/// Text a drag took from the note, kept while the drag lasts.
struct DraggedNoteText: Equatable {
    /// Where the text was in the note when the drag began (UTF-16).
    let range: NSRange
    let text: String
    /// Where the drag was let go over the same note (UTF-16), once it is.
    var dropLocation: Int?
}

/// UIKit moves text dragged within a text view by editing its text storage directly: no undo is
/// recorded, and UIKit's text input then empties the view's undo history, as for any change it
/// did not make (HUNT-377, iPad simulator, 2026-11-24). Such a drop is therefore taken off
/// UIKit's fast path, as a copy; the editor keeps UIKit from inserting the copy (the paste
/// delegate's `transform`, through which drops of text also pass) and moves the text to the
/// place it was let go itself, as one edit through the text view (`DraggedTextMove`).
extension NativeMarkdownEditor.Coordinator: UITextDropDelegate, UITextPasteDelegate {
    /// Takes the drags of `textView`'s text, which also carry the section they start in
    /// (`MarkdownEditorSectionDrag`), and the drops of that text back into the note, which move it.
    func takeDragsAndDrops(of textView: UITextView) {
        textView.textDragDelegate = self
        textView.textDropDelegate = self
        textView.pasteDelegate = self
    }

    func textDroppableView(_ textDroppableView: any UIView & UITextDroppable, proposalForDrop drop: any UITextDropRequest) -> UITextDropProposal {
        guard drop.isSameView, textDraggedWithinNote != nil else { return drop.suggestedProposal }
        // A copy, which the editor turns into the move: it removes the text from its old place itself, in the same step.
        let proposal = UITextDropProposal(operation: .copy)
        proposal.useFastSameViewOperations = false
        return proposal
    }

    func textDroppableView(_ textDroppableView: any UIView & UITextDroppable, willPerformDrop drop: any UITextDropRequest) {
        guard drop.isSameView, textDraggedWithinNote != nil, let textView else { return }
        textDraggedWithinNote?.dropLocation = textView.offset(from: textView.beginningOfDocument, to: drop.dropPosition)
    }

    /// The note's own text let go over it is moved by the editor, and UIKit inserts no copy of
    /// it; anything else pasted or dropped is inserted as UIKit does.
    func textPasteConfigurationSupporting(_ textPasteConfigurationSupporting: any UITextPasteConfigurationSupporting, transform item: any UITextPasteItem) {
        guard let location = textDraggedWithinNote?.dropLocation, let textView else {
            item.setDefaultResult()
            return
        }
        item.setNoResult()
        _ = moveTextDraggedWithinNote(to: location, in: textView)
    }

    /// A drag let go anywhere else leaves nothing to move.
    func textDraggableView(_ textDraggableView: any UIView & UITextDraggable, dragSessionDidEnd session: any UIDragSession, with operation: UIDropOperation) {
        if textDraggedWithinNote?.dropLocation == nil { textDraggedWithinNote = nil }
    }

    /// Notes the text a drag starts with, for a drop back into the note.
    func recordTextDraggedWithinNote(_ range: NSRange, in textView: UITextView) {
        let text = textView.textStorage.string as NSString
        guard range.length > 0, NSMaxRange(range) <= text.length else {
            textDraggedWithinNote = nil
            return
        }
        textDraggedWithinNote = DraggedNoteText(range: range, text: text.substring(with: range))
    }

    /// Moves the dragged text to `location`, a place in the note as it was when the drag was let
    /// go over it, and answers whether it moved. A note changed since the drag began keeps the
    /// text where it is now: the text the drag took may no longer be there.
    func moveTextDraggedWithinNote(to location: Int, in textView: UITextView) -> Bool {
        guard let dragged = textDraggedWithinNote else { return false }
        textDraggedWithinNote = nil
        let text = textView.textStorage.string as NSString
        guard NSMaxRange(dragged.range) <= text.length, text.substring(with: dragged.range) == dragged.text,
              let edit = DraggedTextMove.edit(moving: dragged.range, to: location, in: text) else { return false }
        perform(edit, in: textView)
        return true
    }
}
#endif
