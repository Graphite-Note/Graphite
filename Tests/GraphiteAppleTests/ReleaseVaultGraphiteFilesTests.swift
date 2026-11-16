/**
 * File: ReleaseVaultGraphiteFilesTests.swift
 * ------------------------------------------
 * Layer: Tests
 * Description: The release test vault's files that Graphite's own writers make (drawings, notebooks, PDFs written on,
 *              imports, pictures, folder styles), checked here and written into the vault when
 *              `scripts/make-release-vault.py` asks for them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

#if os(macOS)
import XCTest
import PDFKit
import PencilKit
import AppKit
import GraphiteCore
import GraphiteTestSupport
import GraphiteFixtures
@testable import GraphiteApple

/// The files of `Tests/ReleaseVault` (Docs/Release-test-vault-todo.md, section 1) that Graphite's writers make rather
/// than the vault's Python script: drawings are PNG, SVG and PDF files carrying their Pencil strokes (`GraphitePNG`,
/// `SVGDrawingFile`, `PDFDrawingFile`), notebooks are the PDFs the New Notebook sheet writes (`NewNotebookDocument`),
/// a PDF written on gets its ink, text boxes, pictures, markup and bookmarks from `PDFPageManager`, and imports are the
/// notebook import's own PDFs. Each test writes its files into a temporary folder and checks them; with
/// `GRAPHITE_RELEASE_VAULT_FOLDER` set to the vault, as the script sets it, the files are written into the vault too.
/// The script makes the vault's pictures and slides first; these tests read them from the vault.
final class ReleaseVaultGraphiteFilesTests: XCTestCase {
    static let vaultFolderVariable = "GRAPHITE_RELEASE_VAULT_FOLDER"
    static let drawingPath = "Drawings/Circuit drawing.png"
    static let notebookPath = "Notebooks/Lab notebook.pdf"
    /// The drawing's canvas in points; its PNG is drawn at twice that, as the iPad saves drawings.
    static let drawingSize = CGSize(width: 600, height: 260)
    /// The formula sheet's density on a quarter of its page (`ReleaseVaultWrittenPDF.densePageData`).
    static let densePageStrokeCount = DenseHandwritingNotebook.formulaSheetStrokeCount / 4

    func testTheDrawingIsAPictureThatCarriesItsStrokes() throws {
        let drawingData = try Self.drawingData()
        let decoded = try GraphitePNG.decode(drawingData)
        let payload = try XCTUnwrap(decoded.drawing, "Graphite reads the strokes back, so the drawing opens for editing.")
        XCTAssertEqual(try PKDrawing(data: payload.strokes).strokes.count, Self.drawingStrokes().count)
        let picture = try XCTUnwrap(NSImage(data: decoded.imageData)?.cgImage(forProposedRect: nil, context: nil, hints: nil))
        XCTAssertEqual(picture.width, Int(Self.drawingSize.width) * 2, "Any app shows the PNG, drawn at twice the canvas.")
        try write(drawingData, to: Self.drawingPath)
    }

    func testTheNotebookIsTheNewNotebookSheetsPDFWithACover() throws {
        var options = NewNotebookOptions(paperChoice: .ruledNarrow, paperStyle: PaperSpecification(), pageSize: .named(.a5, .portrait), pageCount: 3)
        options.cover = .blue
        let notebookData = try NewNotebookDocument.data(for: options, titled: "Lab notebook", templateLocation: nil)
        let document = try XCTUnwrap(PDFDocument(data: notebookData))
        XCTAssertEqual(document.pageCount, 4, "A cover and three ruled pages.")
        try write(notebookData, to: Self.notebookPath)
    }

    func testTheDrawingWithEveryToolIsSavedAsPNGSVGAndPDFWithItsStrokes() throws {
        let picture = try vaultFile("Attachments/Square badge.png")
        let files = [("Drawings/Every tool.png", try ReleaseVaultDrawings.pngData(pictureData: picture)),
                     ("Drawings/Every tool.svg", try ReleaseVaultDrawings.svgData(pictureData: picture)),
                     ("Drawings/Every tool.pdf", try ReleaseVaultDrawings.pdfData(pictureData: picture)),
                     ("Drawings/Without paper.png", try ReleaseVaultDrawings.pngData(pictureData: picture, background: .transparent))]
        let strokeCount = ReleaseVaultDrawings.drawing().strokes.count
        XCTAssertGreaterThan(strokeCount, ReleaseVaultDrawings.inkRow.count + 8 + 3, "The eraser cut its line and band into more pieces.")
        for (path, fileData) in files {
            let format = try XCTUnwrap(DrawingFormat(fileExtension: (path as NSString).pathExtension))
            let reading = try DrawingMetadataReader.readMetadata(fileData, format: format)
            let payload = try XCTUnwrap(reading.payload, "\(path) opens for editing.")
            XCTAssertEqual(try PKDrawing(data: payload.strokes).strokes.count, strokeCount, path)
            try write(fileData, to: path)
        }
    }

    func testTheSlidesWrittenOnCarryEveryKindOfGraphitesMarks() throws {
        let slides = try vaultLocation("PDFs/Lecture slides.pdf")
        let written = try ReleaseVaultWrittenPDF.data(fromSlides: slides, picture: try vaultFile("Attachments/Square badge.png"),
                                                      chart: try vaultFile("Attachments/Bar chart.png"), in: try temporaryFolder())
        let document = try XCTUnwrap(PDFDocument(data: written))
        let types = Set((0..<document.pageCount).flatMap { pageIndex in document.page(at: pageIndex)?.annotations.map(\.type) ?? [] })
        XCTAssertTrue(types.isSuperset(of: ["Ink", "Highlight", "Underline", "StrikeOut", "FreeText", "Stamp", "Link"]), "\(types)")
        let outline = try XCTUnwrap(document.outlineRoot)
        let labels = (0..<outline.numberOfChildren).compactMap { childIndex in outline.child(at: childIndex)?.label }
        XCTAssertEqual(labels.suffix(2), ["Page 2", "Page 4"], "The slides' outline, then the two bookmarks.")
        let authors = Set((0..<document.pageCount).flatMap { pageIndex in document.page(at: pageIndex)?.annotations.compactMap(\.userName) ?? [] })
        XCTAssertEqual(authors.subtracting([ReleaseVaultWrittenPDF.authorName]), [], "No annotation names the Mac's account.")
        try write(written, to: "PDFs/Written in Graphite.pdf")
    }

    func testADensePageIsWrittenAsTheFormulaSheetWas() throws {
        let dense = try ReleaseVaultWrittenPDF.densePageData(strokeCount: Self.densePageStrokeCount, in: try temporaryFolder())
        let page = try XCTUnwrap(PDFDocument(data: dense)?.page(at: 0))
        XCTAssertEqual(page.annotations.filter { annotation in annotation.type == "Ink" }.count, Self.densePageStrokeCount)
        try write(dense, to: "PDFs/Dense formula sheet.pdf")
    }

    func testTheProtectedSlidesAndTheFormAreWrittenAsOtherAppsWriteThem() throws {
        let protected = try ReleaseVaultWrittenPDF.protectedData(fromSlides: try vaultLocation("PDFs/Lecture slides.pdf"), in: try temporaryFolder())
        let protectedDocument = try XCTUnwrap(PDFDocument(data: protected))
        XCTAssertTrue(protectedDocument.isEncrypted)
        XCTAssertFalse(protectedDocument.isLocked, "It opens without its password.")
        XCTAssertFalse(protectedDocument.allowsCommenting, "Graphite opens it read-only.")
        try write(protected, to: "PDFs/Protected slides.pdf")
        let form = try ReleaseVaultWrittenPDF.formData()
        XCTAssertEqual(try XCTUnwrap(PDFDocument(data: form)?.page(at: 0)).annotations.filter { annotation in annotation.type == "Widget" }.count, 4)
        try write(form, to: "PDFs/Form.pdf")
    }

    func testANotebookIsMadeOnEveryPaperAndEveryPageSizeOfTheSheet() throws {
        let byPaper = try ReleaseVaultNotebooks.notebooksByPaper(), bySize = try ReleaseVaultNotebooks.notebooksBySize()
        XCTAssertEqual(byPaper.count, NotebookPaperChoice.allCases.count)
        XCTAssertEqual(bySize.count, NotebookPageSize.allCases.count + 1)
        for (path, fileData) in byPaper + bySize {
            XCTAssertNotNil(PDFDocument(data: fileData), path)
            try write(fileData, to: path)
        }
    }

    func testAPaperOfOnesOwnAndANotebookOnItAreMadeAsMyTemplatesMakesThem() throws {
        let folder = try TemporaryVault.make(prefix: "ReleaseVaultMyTemplate", for: self).root
        let files = try ReleaseVaultNotebooks.myTemplateAndNotebook(fromScannedPage: try vaultLocation("PDFs/Scanned page.pdf"), in: folder)
        XCTAssertEqual(files.map { file in try? XCTUnwrap(PDFDocument(data: file.data)).pageCount }, [1, 2])
        for (path, fileData) in files { try write(fileData, to: path) }
    }

    func testTheImportOfEverySyntheticNotebookIsKeptAsItsPDF() throws {
        let folder = try TemporaryVault.make(prefix: "ReleaseVaultImports", for: self).root
        let imports = try ReleaseVaultNotebooks.importedNotebooks(into: folder)
        XCTAssertEqual(imports.count, 4, "Two Goodnotes notebooks and two Notability notes.")
        for (path, fileData) in imports {
            let document = try XCTUnwrap(PDFDocument(data: fileData), path)
            XCTAssertGreaterThan(document.pageCount, 0, path)
            let authors = Set((0..<document.pageCount).flatMap { pageIndex in document.page(at: pageIndex)?.annotations.compactMap(\.userName) ?? [] })
            XCTAssertEqual(authors.subtracting([ReleaseVaultWrittenPDF.authorName]), [], "\(path) names no one's account.")
            try write(fileData, to: path)
        }
    }

    func testPicturesAreMadeInEveryOtherFormatGraphiteOpens() throws {
        let pictures = try ReleaseVaultNotebooks.picturesInOtherFormats()
        XCTAssertTrue(Set(pictures.map { picture in (picture.path as NSString).pathExtension }).isSuperset(of: ["jpg", "gif", "tiff", "heic"]))
        for (path, fileData) in pictures {
            XCTAssertNotNil(NSImage(data: fileData), path)
            try write(fileData, to: path)
        }
    }

    func testTheFolderStylesAreWrittenAsTheLibraryWritesThem() throws {
        let styles = try ReleaseVaultNotebooks.folderStylesData()
        XCTAssertEqual(try FolderStyleList(configurationData: styles).styles.count, 5)
        try write(styles, to: FolderStyleList.configurationPath)
    }

    private func temporaryFolder() throws -> URL {
        try TemporaryVault.make(prefix: "ReleaseVaultFiles", for: self).root
    }

    /// A file the vault's script made, read from the vault being made, or from the repository's.
    private func vaultFile(_ relativePath: String) throws -> Data {
        try Data(contentsOf: try vaultLocation(relativePath))
    }

    private func vaultLocation(_ relativePath: String) throws -> URL {
        let vault = ProcessInfo.processInfo.environment[Self.vaultFolderVariable].map { path in URL(fileURLWithPath: path, isDirectory: true) }
            ?? FixtureFolders.releaseVault
        let location = vault.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: location.path) else {
            throw GraphiteError.unavailable("\(relativePath): run scripts/make-release-vault.py first.")
        }
        return location
    }

    /// Writes the file into a temporary folder, and into the vault when the script asks for it.
    private func write(_ fileData: Data, to relativePath: String) throws {
        let temporaryFolder = try TemporaryVault.make(prefix: "ReleaseVaultFiles", for: self).root
        try fileData.write(to: temporaryFolder.appendingPathComponent((relativePath as NSString).lastPathComponent), options: .atomic)
        guard let vaultPath = ProcessInfo.processInfo.environment[Self.vaultFolderVariable] else { return }
        let destination = URL(fileURLWithPath: vaultPath, isDirectory: true).appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileData.write(to: destination, options: .atomic)
    }

    /// A small circuit in pen: a resistor's zigzag between two wires, a capacitor's plates, and a yellow marker over the
    /// resistor, as a person would sketch it.
    static func drawingStrokes() -> [PKStroke] {
        let black = NSColor.black, blue = NSColor(red: 0.1, green: 0.3, blue: 0.8, alpha: 1)
        let zigzag = [CGPoint(x: 160, y: 120)] + (1...6).map { step in CGPoint(x: 160 + CGFloat(step) * 20, y: step.isMultiple(of: 2) ? 120 : 96) }
        return [stroke(through: [CGPoint(x: 40, y: 120), CGPoint(x: 160, y: 120)], ink: PKInk(.pen, color: black), width: 4),
                stroke(through: zigzag, ink: PKInk(.pen, color: black), width: 4),
                stroke(through: [CGPoint(x: 280, y: 120), CGPoint(x: 400, y: 120)], ink: PKInk(.pen, color: black), width: 4),
                stroke(through: [CGPoint(x: 400, y: 80), CGPoint(x: 400, y: 160)], ink: PKInk(.pen, color: blue), width: 5),
                stroke(through: [CGPoint(x: 420, y: 80), CGPoint(x: 420, y: 160)], ink: PKInk(.pen, color: blue), width: 5),
                stroke(through: [CGPoint(x: 420, y: 120), CGPoint(x: 560, y: 120)], ink: PKInk(.pen, color: black), width: 4),
                stroke(through: [CGPoint(x: 160, y: 108), CGPoint(x: 280, y: 108)], ink: PKInk(.marker, color: .systemYellow), width: 28)]
    }

    private static func stroke(through corners: [CGPoint], ink: PKInk, width: CGFloat) -> PKStroke {
        // Ten points along each straight piece, so the stroke is drawn as the pen moved, not as a jump between corners.
        let points = zip(corners, corners.dropFirst()).flatMap { start, end in
            (0..<10).map { step in
                let fraction = CGFloat(step) / 10
                return CGPoint(x: start.x + (end.x - start.x) * fraction, y: start.y + (end.y - start.y) * fraction)
            }
        } + [corners[corners.count - 1]]
        let controlPoints = points.enumerated().map { pointIndex, location in
            PKStrokePoint(location: location, timeOffset: TimeInterval(pointIndex) / 60, size: CGSize(width: width, height: width),
                          opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        // A fixed date keeps the file the same on every run.
        return PKStroke(ink: ink, path: PKStrokePath(controlPoints: controlPoints, creationDate: Date(timeIntervalSince1970: 1_793_000_000)))
    }

    /// The PNG the iPad would save for the strokes on white paper: drawn at twice the canvas, with the strokes in the chunk.
    static func drawingData() throws -> Data {
        let drawing = PKDrawing(strokes: drawingStrokes())
        let canvas = CGRect(origin: .zero, size: drawingSize)
        // PencilKit draws black ink white in the dark appearance, as on a dark canvas; a drawing is saved as it looks on paper.
        var renderedInk: NSImage?
        NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance { renderedInk = drawing.image(from: canvas, scale: 2) }
        let inkImage = try XCTUnwrap(renderedInk?.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let pixelWidth = Int(drawingSize.width * 2), pixelHeight = Int(drawingSize.height * 2)
        let context = try XCTUnwrap(CGContext(data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        context.draw(inkImage, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        let paperImage = try XCTUnwrap(context.makeImage())
        let payload = DrawingPayload(width: drawingSize.width, height: drawingSize.height, background: .white, strokes: drawing.dataRepresentation())
        return try GraphitePNG.encode(imageData: ImageEncoding.pngData(from: paperImage), drawing: payload)
    }
}
#endif
