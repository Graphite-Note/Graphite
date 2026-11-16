/**
 * File: PDFLinkActions.swift
 * --------------------------
 * Layer: UI
 * Description: Links to pages and quotes for notes, offered in a PDF's text selection menu.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

import SwiftUI
import PDFKit
import GraphiteCore

/// Links to pages and quotes for notes, offered in a PDF's text selection menu.
struct PDFLinkActions {
    /// Copies a link to the page (zero-based).
    let copyLink: (_ pageIndex: Int) -> Void
    /// Copies the selected text as a quote followed by a link to its page.
    let copyQuote: (_ pageIndex: Int, _ text: String) -> Void
    /// Inserts the quote into the note open on the other side, named `noteName`.
    let quoteInNote: ((_ pageIndex: Int, _ text: String) -> Void)?
    let noteName: String?
    /// Adds a picture taken with the lasso to that note, as an attachment.
    var addImageToNote: ((_ pngData: Data, _ name: String) -> Void)? = nil

    /// Where the lasso's pictures of the page can be added: the note open beside the PDF.
    var noteDestination: LassoNoteDestination? {
        guard let addImageToNote, let noteName else { return nil }
        return LassoNoteDestination(noteName: noteName, addImage: addImageToNote)
    }
}

#if canImport(UIKit)
import UIKit

extension PDFLinkActions {
    /// The menu items for text selected on a page.
    @MainActor func menuElements(pageIndex: Int, text: String) -> [UIMenuElement] {
        var elements: [UIMenuElement] = [
            UIAction(title: "Copy Link to Page", image: UIImage(systemName: "link")) { _ in copyLink(pageIndex) },
            UIAction(title: "Copy as Quote", image: UIImage(systemName: "text.quote")) { _ in copyQuote(pageIndex, text) },
        ]
        if let quoteInNote, let noteName {
            elements.append(UIAction(title: "Quote in “\(noteName)”", image: UIImage(systemName: "text.badge.plus")) { _ in quoteInNote(pageIndex, text) })
        }
        return elements
    }
}
#endif
