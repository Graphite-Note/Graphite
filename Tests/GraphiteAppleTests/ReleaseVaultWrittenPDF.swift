/**
 * File: ReleaseVaultWrittenPDF.swift
 * ----------------------------------
 * Layer: Tests
 * Description: The release vault's PDFs written on by Graphite's own PDF writer: the lecture slides with ink of every
 *              tool, a highlighter over text, eraser cuts, shapes, text boxes, pictures, markup, links and bookmarks; a
 *              page written as densely as a formula sheet; a protected copy and a form.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

#if os(macOS)
import Foundation
import AppKit
import PDFKit
import PencilKit
import GraphiteCore
import GraphiteTestSupport
@testable import GraphiteApple

/// Each edit is the one Graphite's PDF view makes (`PDFEdit`), applied to `PDFs/Lecture slides.pdf` (which the vault's
/// script makes first) and written as a save writes them (`PDFPageManager`, `PDFFileService.write`): what a person does
/// to a lecture's slides with Apple Pencil, the text box tool, the picture tool, the markup tools and Bookmark This Page.
/// The files are written in `folder`, a temporary folder of the test.
enum ReleaseVaultWrittenPDF {
    /// The author the annotations name: never a person's own name (`PDFAnnotationAuthor` would take the Mac's account).
    static let authorName = "Release vault"
    /// A suite of its own, where no name is chosen, so the author is `authorName`.
    static var author: PDFAnnotationAuthor {
        PDFAnnotationAuthor(defaults: UserDefaults(suiteName: "ReleaseVaultWrittenPDF") ?? UserDefaults(), ownerName: { authorName })
    }

    /// The slides written on. The edits that make annotations are applied with the vault's author; the bookmarks are
    /// replayed as a save replays them, since PDFKit writes a changed outline only with a rewritten page tree.
    static func data(fromSlides slides: URL, picture: Data, chart: Data, in folder: URL) throws -> Data {
        guard let slidesDocument = PDFDocument(url: slides), slidesDocument.pageCount >= 4 else { throw GraphiteError.invalidFile("The slides are not made yet.") }
        let edits = [try inkEdit(on: 0, of: slidesDocument, drawing: firstPageInk(on: slidesDocument))]
            + textBoxEdits(onPage: 1)
            + (try markupAndPictureEdits(on: slidesDocument, onPage: 2, picture: picture, chart: chart))
            + [try inkEdit(on: 3, of: slidesDocument, drawing: PKDrawing(strokes: ReleaseVaultDrawings.shapeStrokes().map(shiftedOntoSlide)
                                                                            + ReleaseVaultDrawings.lassoMovedStrokes()))]
        guard let document = PDFDocument(url: slides) else { throw GraphiteError.invalidFile("The slides are not made yet.") }
        PDFPageManager.prepareForWriting(document)
        for edit in edits { try apply(edit, to: document) }
        try PDFPageManager.replay([.bookmark(page: 1, label: "Page 2"), .bookmark(page: 3, label: "Page 4")], on: document)
        return try written(document, named: "Written in Graphite.pdf", in: folder)
    }

    /// The first slide: a wave of every ink along its foot, a highlighter over its third bullet, multiplied over the
    /// text, and a pen line under the title cut twice by the eraser.
    private static func firstPageInk(on document: PDFDocument) throws -> PKDrawing {
        guard let page = document.page(at: 0) else { throw GraphiteError.invalidFile("No first slide.") }
        let coordinates = try overlay(of: page)
        let inks = ReleaseVaultDrawings.inkStrokes().dropLast().map { stroke in
            PKStroke(ink: stroke.ink, path: stroke.path, transform: CGAffineTransform(translationX: -10, y: 470), mask: nil)
        }
        var strokes = Array(inks)
        if let bullet = lineBounds(of: "Nyquist: f_s must exceed twice the highest frequency.", on: page).first {
            let top = coordinates.overlayPoint(fromPDF: CGPoint(x: bullet.minX, y: bullet.maxY))
            let height = bullet.height
            let middle = top.y + height / 2
            let highlight = ReleaseVaultDrawings.segmentPoints(from: CGPoint(x: top.x, y: middle), to: CGPoint(x: top.x + bullet.width, y: middle))
            strokes.append(ReleaseVaultDrawings.stroke(through: highlight, ink: PKInk(.marker, color: .systemYellow), width: height + 6, evenPressure: true))
        }
        let underline = ReleaseVaultDrawings.stroke(through: ReleaseVaultDrawings.segmentPoints(from: CGPoint(x: 60, y: 104), to: CGPoint(x: 440, y: 104)),
                                                    ink: PKInk(.pen, color: .systemRed), width: 5)
        var cut = PixelEraserPass.erasing(PKDrawing(strokes: [underline]), along: [CGPoint(x: 180, y: 90), CGPoint(x: 180, y: 118)], width: 14)
        cut = PixelEraserPass.erasing(cut, along: [CGPoint(x: 320, y: 90), CGPoint(x: 320, y: 118)], width: 14)
        return PKDrawing(strokes: strokes + cut.strokes)
    }

    /// The shapes row of the drawing made smaller and moved onto the free space under a slide's bullets.
    private static func shiftedOntoSlide(_ stroke: PKStroke) -> PKStroke {
        PKStroke(ink: stroke.ink, path: stroke.path, transform: CGAffineTransform(a: 0.85, b: 0, c: 0, d: 0.85, tx: 0, ty: 120), mask: nil)
    }

    /// The second slide: text boxes in each kind of font the text box tool offers, one turned, one filled and framed,
    /// and one with a link over a word.
    private static func textBoxEdits(onPage pageIndex: Int) -> [PDFEdit] {
        let dark = PDFTextColor(red: 0.1, green: 0.1, blue: 0.1), red = PDFTextColor(red: 0.7, green: 0.1, blue: 0.1)
        let blue = PDFTextColor(red: 0.1, green: 0.35, blue: 0.7)
        let framed = PDFTextBoxStyle(alignment: .center, fillColor: PDFTextColor(red: 1, green: 0.96, blue: 0.75), borderColor: red, borderWidth: 1.5,
                                     padding: 8)
        let article = URL(string: "https://en.wikipedia.org/wiki/Quantization_(signal_processing)")
        let boxes: [(runs: [PDFTextRun], origin: CGPoint, width: Double, rotation: Double, style: PDFTextBoxStyle)] = [
            ([run("Helvetica: the default box.", PDFTextAttributes(fontFamily: "Helvetica", fontSize: 14, color: dark))],
             CGPoint(x: 540, y: 560), 230, 0, .plain),
            ([run("Georgia, bold, on a filled box with a frame.", PDFTextAttributes(fontFamily: "Georgia", fontSize: 16, color: red, isBold: true))],
             CGPoint(x: 540, y: 500), 230, 0, framed),
            ([run("Courier New, italic and underlined", PDFTextAttributes(fontFamily: "Courier New", fontSize: 12, color: dark, isItalic: true,
                                                                           isUnderlined: true))], CGPoint(x: 540, y: 400), 230, 0, .plain),
            ([run("Avenir Next, turned", PDFTextAttributes(fontFamily: "Avenir Next", fontSize: 18, color: blue))], CGPoint(x: 560, y: 320), 190, 0.25, .plain),
            ([run("Read more on ", PDFTextAttributes(fontFamily: "Menlo", fontSize: 12, color: dark)),
              run("Wikipedia", PDFTextAttributes(fontFamily: "Menlo", fontSize: 12, color: blue, isUnderlined: true, link: article))],
             CGPoint(x: 540, y: 190), 230, 0, .plain),
        ]
        return boxes.enumerated().map { boxIndex, box in
            let textBox = PDFTextBox(name: "release-vault-text-box-\(boxIndex + 1)", runs: box.runs, origin: box.origin, width: box.width, height: 1,
                                     rotationRadians: box.rotation, style: box.style)
            return .addTextBox(page: pageIndex, textBox: PDFTextBoxLayout.fitted(textBox))
        }
    }

    private static func run(_ text: String, _ attributes: PDFTextAttributes) -> PDFTextRun {
        PDFTextRun(text: text, attributes: attributes)
    }

    /// The third slide: a highlight, an underline and a strikeout over three of its lines, as the markup tools make them
    /// from a text selection, and two pictures, one upright and one turned.
    private static func markupAndPictureEdits(on document: PDFDocument, onPage pageIndex: Int, picture: Data, chart: Data) throws -> [PDFEdit] {
        guard let page = document.page(at: pageIndex) else { throw GraphiteError.invalidFile("No third slide.") }
        let marks: [(text: String, kind: PDFMarkupKind, color: PDFMarkupColor)] = [
            ("Poles inside the unit circle", .highlight, .yellow), ("A delay of one sample", .underline, .blue), ("Zeros on the circle", .strikeOut, .red),
            ("X(z) is the sum", .highlight, .green),
        ]
        let markupEdits: [PDFEdit] = try marks.enumerated().map { markIndex, mark in
            let lines = lineBounds(of: mark.text, on: page)
            guard !lines.isEmpty else { throw GraphiteError.invalidFile("“\(mark.text)” is not on the slide.") }
            return .addMarkup(page: pageIndex, markup: PDFMarkup(name: "release-vault-markup-\(markIndex + 1)", kind: mark.kind, color: mark.color, lineBounds: lines))
        }
        return markupEdits + [
            .addPicture(page: pageIndex, picture: PDFPicture(name: "release-vault-picture-1", imageData: picture,
                                                             bounds: CGRect(x: 600, y: 420, width: 120, height: 120), quarterTurns: 0)),
            .addPicture(page: pageIndex, picture: PDFPicture(name: "release-vault-picture-2", imageData: chart,
                                                             bounds: CGRect(x: 560, y: 80, width: 180, height: 120), quarterTurns: 0, rotationRadians: 0.3)),
        ]
    }

    // MARK: Dense, protected and form

    /// A page written as densely as the formula sheet imported on 2026-11-12 (6,000 strokes on an A3 page), with the
    /// strokes of `DenseHandwritingNotebook`, saved as a page's ink is saved. The page is a quarter of A3, A5 across, so
    /// a quarter of the strokes give the same density in a quarter of the bytes. `DenseHandwritingNotebook.write` would
    /// name the Mac's account as the author, so the page is written here with the vault's.
    static func densePageData(strokeCount: Int, in folder: URL) throws -> Data {
        let pageSize = CGSize(width: DenseHandwritingNotebook.pageSize.width / 2, height: DenseHandwritingNotebook.pageSize.height / 2)
        guard let document = PDFDocument(data: try DenseHandwritingNotebook.blankPages(count: 1, size: pageSize)) else {
            throw GraphiteError.invalidFile("The blank page could not be read.")
        }
        PDFPageManager.prepareForWriting(document)
        try apply(inkEdit(on: 0, of: document, drawing: DenseHandwritingNotebook.drawing(strokeCount: strokeCount, pageSize: pageSize)), to: document)
        return try written(document, named: "Dense formula sheet.pdf", in: folder)
    }

    /// The slides with an owner password and only printing allowed: Graphite opens such a PDF read-only, without asking
    /// for the password, which is a made-up value of this test.
    static func protectedData(fromSlides slides: URL, in folder: URL) throws -> Data {
        guard let document = PDFDocument(url: slides) else { throw GraphiteError.invalidFile("The slides are not made yet.") }
        let destination = folder.appendingPathComponent("Protected slides.pdf")
        let options: [PDFDocumentWriteOption: Any] = [.ownerPasswordOption: "release-vault-owner",
                                                      .accessPermissionsOption: PDFAccessPermissions.allowsLowQualityPrinting.rawValue]
        guard document.write(to: destination, withOptions: options) else { throw GraphiteError.invalidFile("The protected copy could not be saved.") }
        return try Data(contentsOf: destination)
    }

    /// A one-page form: a text field, two check boxes and a choice, which Graphite shows as they are, read-only.
    static func formData() throws -> Data {
        guard let document = PDFDocument(data: try DenseHandwritingNotebook.blankPages(count: 1, size: CGSize(width: 595, height: 842))),
              let page = document.page(at: 0) else { throw GraphiteError.invalidFile("The form's page could not be made.") }
        let name = PDFAnnotation(bounds: CGRect(x: 60, y: 720, width: 300, height: 28), forType: .widget, withProperties: nil)
        name.widgetFieldType = .text
        name.fieldName = "Lab group"
        name.widgetStringValue = "Group 4"
        page.addAnnotation(name)
        for (boxIndex, isChecked) in [true, false].enumerated() {
            let checkBox = PDFAnnotation(bounds: CGRect(x: 60, y: 660 - Double(boxIndex) * 40, width: 22, height: 22), forType: .widget, withProperties: nil)
            checkBox.widgetFieldType = .button
            checkBox.widgetControlType = .checkBoxControl
            checkBox.fieldName = "Checked \(boxIndex + 1)"
            checkBox.buttonWidgetState = isChecked ? .onState : .offState
            page.addAnnotation(checkBox)
        }
        let choice = PDFAnnotation(bounds: CGRect(x: 60, y: 540, width: 200, height: 28), forType: .widget, withProperties: nil)
        choice.widgetFieldType = .choice
        choice.fieldName = "Session"
        choice.choices = ["Monday", "Thursday"]
        choice.widgetStringValue = "Thursday"
        page.addAnnotation(choice)
        guard let written = document.dataRepresentation() else { throw GraphiteError.invalidFile("The form could not be saved.") }
        return written
    }

    // MARK: Helpers

    /// The document as a save writes it, compacted (`PDFFileService.write`).
    static func written(_ document: PDFDocument, named name: String, in folder: URL) throws -> Data {
        let destination = folder.appendingPathComponent(name)
        guard PDFFileService.write(document, to: destination) else { throw GraphiteError.invalidFile("\(name) could not be saved.") }
        return try Data(contentsOf: destination)
    }

    /// The ink edit the page's canvas makes when its drawing changes to `drawing`.
    private static func inkEdit(on pageIndex: Int, of document: PDFDocument, drawing: PKDrawing) throws -> PDFEdit {
        guard let page = document.page(at: pageIndex) else { throw GraphiteError.invalidFile("No page \(pageIndex + 1).") }
        var tracker = PDFPageInkTracker(group: PDFInkGroups.newGroup(on: page))
        return .updateInk(tracker.update(for: drawing, pageIndex: pageIndex, coordinates: try overlay(of: page)))
    }

    private static func apply(_ edit: PDFEdit, to document: PDFDocument) throws {
        try PDFPageManager.apply(edit, to: document, drawsInkOutlines: true, author: author)
    }

    /// The page's overlay, which counts down from its top-left corner in points, as the PDF view's canvas does.
    private static func overlay(of page: PDFPage) throws -> PageCoordinates {
        let cropBox = page.bounds(for: .cropBox)
        return try PageCoordinates(cropBox: cropBox, overlaySize: cropBox.size)
    }

    /// The rectangles of each line of the first match of `text` on the page, as a text selection gives them.
    static func lineBounds(of text: String, on page: PDFPage) -> [CGRect] {
        guard let pageText = page.string, let range = pageText.range(of: text),
              let selection = page.selection(for: NSRange(range, in: pageText)) else { return [] }
        return selection.selectionsByLine().map { line in line.bounds(for: page) }
    }
}
#endif
