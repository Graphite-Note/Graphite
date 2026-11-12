import Foundation
import PDFKit
import GraphiteCore
import NotebookImport

/// Writes an imported notebook as a new ordinary PDF that Graphite's own PDF code wrote: each planned page is a PDF
/// page of its size with its background as page content (`ImportedBackgroundPages`), its pictures are Graphite's
/// picture stamps (`ImportedPagePictures`), its strokes are standard `/Ink` annotations over them with Graphite's
/// re-editing record (`ImportedPageInk`), and its typed text is Graphite's text boxes over the ink (`ImportedPageText`),
/// so the PDF opens, re-edits and saves like a notebook made in Graphite. Typed text that flows past the last page
/// (Notability's body text) gets pages of its own. A page whose plan leaves it out is not written, and the notebook's
/// outline entries become the PDF's first outline items (`ImportedOutlineItems`).
///
/// Pages are planned, made and applied one at a time; a page's plan and PencilKit drawing are released once the page
/// has its ink. The PDFKit document being written still grows with the notebook. The file is written as
/// `PDFFileService` writes a copy: verified and compacted, then moved into place only when nothing is at the
/// destination. The notebook's files are only read.
///
/// Synchronous and long: run it away from the main actor. It stops between pages when its task is cancelled.
public struct NotebookImportWriter: Sendable {
    private let fileWriter: AtomicFileWriter

    public init(fileWriter: AtomicFileWriter) {
        self.fileWriter = fileWriter
    }

    /// - Parameters:
    ///   - sourcePageCount: How many pages the source has; `outcomeForPage` is asked for each index from 0, in order. A
    ///     page its outcome leaves out is not written and keeps its report.
    ///   - outline: The notebook's outline entries, written before the bookmarks.
    ///   - sourceFiles: Reads the files the plans' backgrounds and pictures name.
    ///   - strokeCreationDate: The PencilKit creation date of every imported stroke.
    public func write(sourcePageCount: Int, outcomeForPage: (Int) throws -> ImportedPageOutcome, outline: [ImportedOutlineEntry],
                      sourceFiles: any ImportSourceFiles, strokeCreationDate: Date, to destination: URL) throws -> NotebookImportWriting {
        guard sourcePageCount > 0 else { throw NotebookImportWriterError.noPages }
        // Checked first so a notebook is not converted only to be refused; the writer checks again as it moves the file.
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw NotebookImportWriterError.destinationExists(destination) }
        var pageReports: [ImportedPageReport] = []
        var notebookEntries: [ImportReportEntry] = []
        do {
            let revision = try fileWriter.replace(destination, expecting: .absent) { staging in
                var written = DocumentBeingWritten(sourceFiles: sourceFiles, strokeCreationDate: strokeCreationDate)
                for sourcePageIndex in 0..<sourcePageCount {
                    try Task.checkCancellation()
                    pageReports.append(try autoreleasepool { try written.append(try outcomeForPage(sourcePageIndex)) })
                }
                // Typed text that flows past the last page gets pages of its own, numbered after the source's.
                pageReports += try written.appendPagesForTheTextLeft(numberedFrom: sourcePageCount + 1)
                let document = written.document
                guard document.pageCount > 0 else { throw NotebookImportWriterError.noPages }
                let outlineEntriesWithoutPage = ImportedOutlineItems.insert(outline, into: document,
                                                                            pageIndexBySourcePageNumber: written.pageIndexBySourcePageNumber)
                if outlineEntriesWithoutPage > 0 { notebookEntries.append(.outlineEntriesWithoutPage(count: outlineEntriesWithoutPage)) }
                guard PDFFileService.write(document, to: staging) else { throw NotebookImportWriterError.verificationFailed(pageCount: document.pageCount) }
            }
            return NotebookImportWriting(revision: revision, pageReports: pageReports, notebookEntries: notebookEntries)
        } catch GraphiteError.conflict {
            throw NotebookImportWriterError.destinationExists(destination)
        }
    }
}

/// The PDF of one write as its pages are added: the document, the backgrounds' source PDFs, and the typed text still
/// flowing onto the next page.
private struct DocumentBeingWritten {
    let document = PDFDocument()
    let sourceFiles: any ImportSourceFiles
    let strokeCreationDate: Date
    private var backgrounds: ImportedBackgroundPages
    private var flowingText = ImportedFlowingTextPlacement()
    private(set) var pageIndexBySourcePageNumber: [Int: Int] = [:]

    init(sourceFiles: any ImportSourceFiles, strokeCreationDate: Date) {
        self.sourceFiles = sourceFiles
        self.strokeCreationDate = strokeCreationDate
        backgrounds = ImportedBackgroundPages(sourceFiles: sourceFiles)
    }

    /// A planned page is added; a page its plan leaves out keeps its report.
    mutating func append(_ outcome: ImportedPageOutcome) throws -> ImportedPageReport {
        switch outcome {
        case .planned(let plan):
            pageIndexBySourcePageNumber[plan.sourcePageNumber] = document.pageCount
            return try appendPage(plan)
        case .leftOut(let sourcePageNumber, let report):
            return ImportedPageReport.leftOut(sourcePageNumber: sourcePageNumber, entries: report)
        }
    }

    /// Pages of the note's paper for the typed text the source's pages could not hold, until none is left.
    mutating func appendPagesForTheTextLeft(numberedFrom firstPageNumber: Int) throws -> [ImportedPageReport] {
        var reports: [ImportedPageReport] = []
        while let plan = flowingText.continuationPlan(sourcePageNumber: firstPageNumber + reports.count) {
            try Task.checkCancellation()
            reports.append(try autoreleasepool { try appendPage(plan) })
        }
        return reports
    }

    /// The pictures go on the page before its ink, and the text boxes after it, so the ink is over the pictures and the
    /// text over both (invariant M-15, and decision 5 of `Docs/PDF-text-boxes-todo.md`). A bookmarked page gets the
    /// outline item Graphite adds for a bookmark, so the PDF's bookmarks follow the pages' order.
    private mutating func appendPage(_ plan: ImportedPagePlan) throws -> ImportedPageReport {
        let pageIndex = document.pageCount
        document.insert(try backgrounds.page(for: plan, pageIndex: pageIndex), at: pageIndex)
        if plan.isBookmarked {
            try PDFPageManager.apply(.bookmark(page: pageIndex, label: PDFPageManager.bookmarkLabelPrefix + "\(pageIndex + 1)"), to: document)
        }
        let picturesLeftOut = try ImportedPagePictures.place(plan.pictures, onPageAt: pageIndex, of: document, pageSize: plan.sizeInPoints,
                                                             sourceFiles: sourceFiles)
        try ImportedPageInk.apply(plan.strokes, toPageAt: pageIndex, of: document, pageSize: plan.sizeInPoints, strokeCreationDate: strokeCreationDate)
        var text = try ImportedPageText.place(plan.textBoxes, onPageAt: pageIndex, of: document, pageSize: plan.sizeInPoints)
        var flowingTextTop = 0.0
        if let startingText = plan.flowingText {
            text.add(flowingText.start(startingText))
            flowingTextTop = startingText.top
        }
        text.add(try flowingText.placeLines(onPageAt: pageIndex, of: document, pageSize: plan.sizeInPoints, top: flowingTextTop))
        let placedPictureCount = plan.pictures.count - picturesLeftOut.missingFileCount - picturesLeftOut.notDecodableCount
        return ImportedPageReport(sourcePageNumber: plan.sourcePageNumber,
                                  written: ImportedPageContents(strokeCount: plan.strokes.count, pictureCount: placedPictureCount,
                                                                textBoxCount: text.boxCount, isBookmarked: plan.isBookmarked),
                                  entries: ImportedPageText.report(ImportedPagePictures.report(plan.report, adding: picturesLeftOut), adding: text))
    }
}
