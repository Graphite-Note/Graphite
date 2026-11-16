/**
 * File: ImportedPaperDocument.swift
 * ---------------------------------
 * Layer: Apple
 * Description: The papers of an imported notebook's pages gathered into one PDF read back from its own bytes, so the
 *              document the import writes owns its pages and PDFKit writes their thousands of strokes in linear time.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */
import Foundation
import PDFKit
import NotebookImport

/// The papers of a notebook's planned pages, in order, with the notebook's outline and bookmarks, before anything is put
/// on them.
///
/// PDFKit writes a page it did not read from the document being written, as an imported page inserted into a new
/// `PDFDocument` is, by making each annotation's dictionary again, and each one asks whether it crosses the page's
/// redaction path, which PDFKit builds again from every annotation of the page: writing such a page costs the square
/// of its strokes (BUG-IMPORT-03). Two pages of 2,000 strokes took 6.2 s on the Mac, two of 6,000 took 42 s, and the
/// owner's formula sheet (5,159 and 6,145 strokes) "took forever" on the iPad. A page of the document's own is written
/// in linear time: so the papers are gathered into a document of their own, which is written to bytes and read back,
/// and the strokes, pictures and text go onto the pages read back. PDFKit writes an outline added to a document read
/// from bytes only with a rewritten page tree (`PDFPageManager.replay`), so the outline and the bookmarks are made here,
/// on the papers.
struct ImportedPaperDocument {
    private let papers = PDFDocument()
    private var backgrounds: ImportedBackgroundPages
    private(set) var pageIndexBySourcePageNumber: [Int: Int] = [:]

    init(sourceFiles: any ImportSourceFiles) {
        backgrounds = ImportedBackgroundPages(sourceFiles: sourceFiles)
    }

    /// The plan's paper becomes the next page; a bookmarked page gets the outline item Graphite adds for a bookmark, so
    /// the PDF's bookmarks follow the pages' order.
    mutating func add(paperOf plan: ImportedPagePlan) throws {
        let pageIndex = papers.pageCount
        papers.insert(try backgrounds.page(for: plan, pageIndex: pageIndex), at: pageIndex)
        pageIndexBySourcePageNumber[plan.sourcePageNumber] = pageIndex
        if plan.isBookmarked {
            try PDFPageManager.apply(.bookmark(page: pageIndex, label: PDFPageManager.bookmarkLabelPrefix + "\(pageIndex + 1)"), to: papers)
        }
    }

    /// The papers with the notebook's outline entries before the bookmarks (`ImportedOutlineItems`), read back from their
    /// own bytes, ready to be written on (`PDFPageManager.prepareForWriting`): an empty document when no page was
    /// planned. Also how many outline entries name a page that was not planned, which are left out.
    func documentToWriteOn(outline: [ImportedOutlineEntry]) throws -> (document: PDFDocument, outlineEntriesWithoutPage: Int) {
        guard papers.pageCount > 0 else {
            let document = PDFDocument()
            PDFPageManager.prepareForWriting(document)
            return (document, outline.count)
        }
        let outlineEntriesWithoutPage = ImportedOutlineItems.insert(outline, into: papers, pageIndexBySourcePageNumber: pageIndexBySourcePageNumber)
        guard let paperBytes = papers.dataRepresentation(), let document = PDFDocument(data: paperBytes) else {
            throw NotebookImportWriterError.verificationFailed(pageCount: papers.pageCount)
        }
        PDFPageManager.prepareForWriting(document)
        guard document.pageCount == papers.pageCount else { throw NotebookImportWriterError.verificationFailed(pageCount: papers.pageCount) }
        return (document, outlineEntriesWithoutPage)
    }
}
