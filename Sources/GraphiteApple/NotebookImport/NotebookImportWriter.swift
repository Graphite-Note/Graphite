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
/// Every page is planned first and its paper gathered (`ImportedPaperDocument`), so the document written owns its pages
/// and PDFKit writes them in time linear in their strokes; then each page gets its pictures, ink and text, and its plan
/// and PencilKit drawing are released once it has them. The notebook's plans are held together meanwhile: about 3 KB a
/// stroke, 140 MB for the densest sample notebook's 46,101 strokes. The file is written as `PDFFileService` writes a
/// copy: verified and compacted, then moved into place only when nothing is at the destination. The notebook's files
/// are only read.
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
    ///   - pageWillBeWritten: Hears each source page's index, in order, before its strokes, pictures and text are written.
    public func write(sourcePageCount: Int, outcomeForPage: (Int) throws -> ImportedPageOutcome, outline: [ImportedOutlineEntry],
                      sourceFiles: any ImportSourceFiles, strokeCreationDate: Date, to destination: URL,
                      pageWillBeWritten: (Int) -> Void = { _ in }) throws -> NotebookImportWriting {
        guard sourcePageCount > 0 else { throw NotebookImportWriterError.noPages }
        // Checked first so a notebook is not converted only to be refused; the writer checks again as it moves the file.
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw NotebookImportWriterError.destinationExists(destination) }
        var pageReports: [ImportedPageReport] = []
        var notebookEntries: [ImportReportEntry] = []
        do {
            let revision = try fileWriter.replace(destination, expecting: .absent) { staging in
                var papers = ImportedPaperDocument(sourceFiles: sourceFiles)
                var outcomes: [ImportedPageOutcome?] = []
                for sourcePageIndex in 0..<sourcePageCount {
                    try Task.checkCancellation()
                    let outcome = try autoreleasepool { try outcomeForPage(sourcePageIndex) }
                    if case .planned(let plan) = outcome { try autoreleasepool { try papers.add(paperOf: plan) } }
                    outcomes.append(outcome)
                }
                let paperDocument = try papers.documentToWriteOn(outline: outline)
                if paperDocument.outlineEntriesWithoutPage > 0 {
                    notebookEntries.append(.outlineEntriesWithoutPage(count: paperDocument.outlineEntriesWithoutPage))
                }
                var written = DocumentBeingWritten(document: paperDocument.document, sourceFiles: sourceFiles, strokeCreationDate: strokeCreationDate)
                for sourcePageIndex in outcomes.indices {
                    try Task.checkCancellation()
                    guard let outcome = outcomes[sourcePageIndex] else { continue }
                    // Released as soon as it is written: a dense page's plan holds megabytes.
                    outcomes[sourcePageIndex] = nil
                    pageWillBeWritten(sourcePageIndex)
                    pageReports.append(try autoreleasepool { try written.append(outcome) })
                }
                // Typed text that flows past the last page gets pages of its own, numbered after the source's.
                pageReports += try written.appendPagesForTheTextLeft(numberedFrom: sourcePageCount + 1)
                let document = written.document
                guard document.pageCount > 0 else { throw NotebookImportWriterError.noPages }
                guard PDFFileService.write(document, to: staging) else { throw NotebookImportWriterError.verificationFailed(pageCount: document.pageCount) }
            }
            return NotebookImportWriting(revision: revision, pageReports: pageReports, notebookEntries: notebookEntries)
        } catch GraphiteError.conflict {
            throw NotebookImportWriterError.destinationExists(destination)
        }
    }
}

/// The PDF of one write as its pages are written on: the document of the planned pages' papers, the backgrounds' source
/// PDFs for pages of text left over, and the typed text still flowing onto the next page.
private struct DocumentBeingWritten {
    let document: PDFDocument
    let sourceFiles: any ImportSourceFiles
    let strokeCreationDate: Date
    private var backgrounds: ImportedBackgroundPages
    private var flowingText = ImportedFlowingTextPlacement()
    /// How many pages have their contents: the next planned page is the paper at this index.
    private var pagesWrittenOn = 0

    /// `document` holds every planned page's paper, in order (`ImportedPaperDocument`).
    init(document: PDFDocument, sourceFiles: any ImportSourceFiles, strokeCreationDate: Date) {
        self.document = document
        self.sourceFiles = sourceFiles
        self.strokeCreationDate = strokeCreationDate
        backgrounds = ImportedBackgroundPages(sourceFiles: sourceFiles)
    }

    /// A planned page is written on; a page its plan leaves out keeps its report.
    mutating func append(_ outcome: ImportedPageOutcome) throws -> ImportedPageReport {
        switch outcome {
        case .planned(let plan):
            return try appendPage(plan, addsBookmark: false)
        case .leftOut(let sourcePageNumber, let report):
            return ImportedPageReport.leftOut(sourcePageNumber: sourcePageNumber, entries: report)
        }
    }

    /// Pages of the note's paper for the typed text the source's pages could not hold, until none is left.
    mutating func appendPagesForTheTextLeft(numberedFrom firstPageNumber: Int) throws -> [ImportedPageReport] {
        var reports: [ImportedPageReport] = []
        while let plan = flowingText.continuationPlan(sourcePageNumber: firstPageNumber + reports.count) {
            try Task.checkCancellation()
            // A page of text holds a few annotations: its paper is inserted as it comes.
            document.insert(try backgrounds.page(for: plan, pageIndex: pagesWrittenOn), at: pagesWrittenOn)
            reports.append(try autoreleasepool { try appendPage(plan, addsBookmark: plan.isBookmarked) })
        }
        return reports
    }

    /// The page at the next index gets its contents: the pictures before its ink, and the text boxes after it, so the ink
    /// is over the pictures and the text over both (invariant M-15, and decision 5 of `Docs/PDF-text-boxes-todo.md`). A
    /// planned page's bookmark was made with its paper (`ImportedPaperDocument`); a page of text left over adds its own.
    private mutating func appendPage(_ plan: ImportedPagePlan, addsBookmark: Bool) throws -> ImportedPageReport {
        let pageIndex = pagesWrittenOn
        pagesWrittenOn += 1
        if addsBookmark {
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
