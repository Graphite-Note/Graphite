/**
 * File: ReleaseVaultGraphiteFilesTests.swift
 * ------------------------------------------
 * Layer: Tests
 * Description: The release test vault's files that Graphite's own writers make, a Pencil drawing and a new notebook,
 *              checked here and written into the vault when `scripts/make-release-vault.py` asks for them.
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
@testable import GraphiteApple

/// The drawing and the notebook of `Tests/ReleaseVault` (Docs/Release-test-vault-todo.md, section 1) are made by
/// Graphite's writers rather than by the vault's Python script: a drawing is a PNG carrying its Pencil strokes in
/// Graphite's `grPK` chunk (`GraphitePNG`), and a notebook is the PDF the New Notebook sheet writes
/// (`NewNotebookDocument`). Each test writes its file into a temporary folder and checks it; with
/// `GRAPHITE_RELEASE_VAULT_FOLDER` set to the vault, as the script sets it, the file is written into the vault too.
final class ReleaseVaultGraphiteFilesTests: XCTestCase {
    static let vaultFolderVariable = "GRAPHITE_RELEASE_VAULT_FOLDER"
    static let drawingPath = "Drawings/Circuit drawing.png"
    static let notebookPath = "Notebooks/Lab notebook.pdf"
    /// The drawing's canvas in points; its PNG is drawn at twice that, as the iPad saves drawings.
    static let drawingSize = CGSize(width: 600, height: 260)

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

    /// Writes the file into a temporary folder, and into the vault when the script asks for it.
    private func write(_ fileData: Data, to relativePath: String) throws {
        let temporaryFolder = try TemporaryVault.make(prefix: "ReleaseVaultFiles", for: self).root
        try fileData.write(to: temporaryFolder.appendingPathComponent((relativePath as NSString).lastPathComponent))
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
