/**
 * File: MarkdownEditorSectionDrag.swift
 * -------------------------------------
 * Layer: UI
 * Description: Text dragged out of a note's editor also carries the section it starts in, so a PDF page it is dropped
 *              on links to the section; the block it starts in gets its identifier only once the page reads it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 21/11/2026
 */

import Foundation
import GraphiteCore

/// The section a drag from a note's text carries, and the edit that names its block.
@MainActor
enum MarkdownEditorSectionDrag {
    /// The section a drag starting at `location` links to, for `register`.
    static func transfer(startingAt location: Int, in session: MarkdownSession) -> (SectionLinkTransfer, identifierEdit: MarkdownTextEdit?) {
        let result = SectionLink.link(startingAt: location, in: session.text, notePath: session.path)
        return (SectionLinkTransfer(link: result.link, vaultRoot: session.vaultRoot), result.identifierEdit)
    }

    /// Gives the block its identifier, once a page reads the drag: through the editor, so it
    /// can be undone, with the cursor left where it was. A note changed since the drag began
    /// is left alone: the block may have moved.
    static func addIdentifier(_ edit: MarkdownTextEdit?, to session: MarkdownSession, expectingText text: String) {
        guard let edit, session.text == text else { return }
        let selection = session.selection
        let insertedLength = (edit.replacement as NSString).length - edit.range.length
        let keptSelection = NSRange(location: selection.location >= NSMaxRange(edit.range) ? selection.location + insertedLength : selection.location,
                                    length: selection.length)
        session.apply(MarkdownTextEdit(range: edit.range, replacement: edit.replacement, selectionAfter: keptSelection))
    }
}

#if canImport(UIKit)
import UIKit

extension NativeMarkdownEditor.Coordinator: UITextDragDelegate {
    /// The text's own drag items, the first also carrying the section the drag starts in.
    func textDraggableView(_ textDraggableView: any UIView & UITextDraggable, itemsForDrag dragRequest: any UITextDragRequest) -> [UIDragItem] {
        let items = dragRequest.suggestedItems
        guard let textView, let firstItem = items.first else { return items }
        let location = textView.offset(from: textView.beginningOfDocument, to: dragRequest.dragRange.start)
        let session = session
        let text = session.text
        let (transfer, identifierEdit) = MarkdownEditorSectionDrag.transfer(startingAt: location, in: session)
        SectionLinkTransfer.register(transfer, on: firstItem.itemProvider) {
            MarkdownEditorSectionDrag.addIdentifier(identifierEdit, to: session, expectingText: text)
        }
        return items
    }
}
#endif

#if os(macOS)
import AppKit

/// A drag of the text carries its section beside the text, written as the drag begins. The
/// block's identifier is added only when a PDF page takes the drop (`MacPDFPictureDropTarget`
/// asks the drag's source view, `prepareSectionDrag`).
extension MarkdownMacTextView {
    override func dragSelection(with event: NSEvent, offset mouseOffset: NSSize, slideBack: Bool) -> Bool {
        pendingSectionDrag = sectionLinkForDrag?(selectedRange().location) ?? nil
        return super.dragSelection(with: event, offset: mouseOffset, slideBack: slideBack)
    }

    override var writablePasteboardTypes: [NSPasteboard.PasteboardType] {
        pendingSectionDrag == nil ? super.writablePasteboardTypes : super.writablePasteboardTypes + [MacPDFPictureDropTarget.sectionLinkType]
    }

    override func writeSelection(to pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        guard type == MacPDFPictureDropTarget.sectionLinkType else { return super.writeSelection(to: pboard, type: type) }
        guard let transfer = pendingSectionDrag?.transfer,
              let encoded = try? JSONEncoder().encode(transfer) else { return false } // Two strings and an address always encode.
        return pboard.setData(encoded, forType: type)
    }

    override func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        super.draggingSession(session, endedAt: screenPoint, operation: operation)
        pendingSectionDrag = nil
    }

    /// Gives the dragged block its identifier, once a page takes the drop.
    func prepareSectionDrag() {
        pendingSectionDrag?.prepare()
    }
}
#endif
