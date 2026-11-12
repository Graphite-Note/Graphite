/**
 * File: DenseInkWritingTests.swift
 * --------------------------------
 * Layer: Tests
 * Description: A notebook written as densely as a formula sheet is imported in time linear in its strokes and into a
 *              file no larger than its strokes, and every save of a PDF read from a file writes a stroke as compactly.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */
import XCTest
import PDFKit
import PencilKit
import GraphiteCore
import NotebookImport
import GraphiteTestSupport
@testable import GraphiteApple

/// BUG-IMPORT-03 and the room a stroke takes. The owner's import of a Goodnotes formula sheet (5,159 and 6,145 strokes
/// on two pages) "took forever" on the iPad on 2026-11-12: PDFKit wrote a page it did not read from the document being
/// written in time that grows with the square of its strokes. Measured on the Mac (debug build) before the fix: two
/// pages of 2,000 strokes 6.2 s, two of 6,000 42.3 s; after it, 3.1 s and 9.0 s.
final class DenseInkWritingTests: XCTestCase {
    private struct NoFiles: ImportSourceFiles {
        struct MissingFile: Error {}

        func contents(of file: ImportedSourceFile) throws -> Data {
            throw MissingFile()
        }
    }

    /// A page plan of `strokeCount` handwritten strokes, each with its outline as Goodnotes gives one.
    private static func densePlan(strokeCount: Int, sourcePageNumber: Int = 1) -> ImportedPagePlan {
        let drawing = DenseHandwritingNotebook.drawing(strokeCount: strokeCount, seed: UInt64(sourcePageNumber))
        let strokes = drawing.strokes.map { stroke -> ImportedStroke in
            let samples = stroke.path.map { point in
                ImportedStrokeSample(location: point.location, width: Double(point.size.width), force: nil, azimuthRadians: nil, altitudeRadians: nil)
            }
            let outline = StrokeOutliner.subpaths(forSamples: samples.map { sample in VectorStrokeSample(point: sample.location, width: sample.width) })
            return ImportedStroke(ink: .pen, color: NotebookImportColor(red: 0, green: 0, blue: 0, alpha: 1), samples: samples, outline: outline)
        }
        return ImportedPagePlan(sourcePageNumber: sourcePageNumber, sizeInPoints: DenseHandwritingNotebook.pageSize,
                                background: .plainColor(NotebookImportColor(red: 1, green: 1, blue: 1, alpha: 1)), strokes: strokes, report: [])
    }

    /// Writes the plans as an import does and returns the seconds it took.
    private func importSeconds(of plans: [ImportedPagePlan], to destination: URL) throws -> Double {
        let start = ContinuousClock.now
        var announcedPages: [Int] = []
        _ = try NotebookImportWriter(fileWriter: AtomicFileWriter()).write(sourcePageCount: plans.count, outcomeForPage: { pageIndex in .planned(plans[pageIndex]) },
                                                                           outline: [], sourceFiles: NoFiles(), strokeCreationDate: Date(timeIntervalSince1970: 0),
                                                                           to: destination, pageWillBeWritten: { pageIndex in announcedPages.append(pageIndex) })
        XCTAssertEqual(announcedPages, Array(plans.indices), "Each page is announced, in order, as it is written.")
        let duration = ContinuousClock.now - start
        return Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    /// Four times the strokes take about four times as long, not sixteen: under 6 times is linear with room for noise.
    /// Measured 2026-11-12: 3.6 times. Before the fix three times the strokes took 6.8 times as long (two pages of 2,000
    /// and of 6,000 strokes: 6.2 s and 42.3 s).
    func testADensePageIsImportedInTimeLinearInItsStrokes() throws {
        let vault = try TemporaryVault.make(prefix: "DenseInkWriting", for: self)
        let lightSeconds = try importSeconds(of: [Self.densePlan(strokeCount: 1_000)], to: vault.location(of: "Light.pdf"))
        let denseSeconds = try importSeconds(of: [Self.densePlan(strokeCount: 4_000)], to: vault.location(of: "Dense.pdf"))
        print("DenseInkWritingTests timing: 1,000 strokes \(String(format: "%.2f", lightSeconds)) s, 4,000 strokes \(String(format: "%.2f", denseSeconds)) s")
        XCTAssertLessThan(denseSeconds, lightSeconds * 6, "Writing a page grows linearly with its strokes.")
        let page = try XCTUnwrap(PDFDocument(url: vault.location(of: "Dense.pdf"))?.page(at: 0))
        XCTAssertEqual(page.annotations.filter { annotation in annotation.type == "Ink" }.count, 4_000)
        let editableGroup = try XCTUnwrap(PDFInkGroups.editableGroup(on: page), "The strokes are Graphite's to edit again.")
        XCTAssertEqual(editableGroup.record.strokeNames.count, 4_000)
    }

    /// The imported file holds each stroke once: no markup copy of its annotation and one colour profile for every
    /// stroke's appearance. With them a stroke took 8.3 KB (measured on two pages of 2,000 strokes, 33.2 MB).
    func testAnImportedStrokeTakesTheRoomOfItsAnnotationAndAppearanceAlone() throws {
        let vault = try TemporaryVault.make(prefix: "DenseInkWriting", for: self)
        let destination = vault.location(of: "Imported.pdf")
        _ = try importSeconds(of: [Self.densePlan(strokeCount: 1_000), Self.densePlan(strokeCount: 1_000, sourcePageNumber: 2)], to: destination)
        let fileBytes = try Data(contentsOf: destination)
        let bytesPerStroke = Double(fileBytes.count) / 2_000
        print("DenseInkWritingTests size: \(fileBytes.count) bytes, \(Int(bytesPerStroke)) a stroke")
        XCTAssertNil(fileBytes.range(of: Data("AAPL:AKExtras".utf8)), "No stroke carries Apple's markup copy.")
        XCTAssertLessThanOrEqual(Self.colorProfileObjectCount(in: fileBytes), 2, "The strokes' appearances share their colour profile.")
        // 2.6 KB measured: the annotation, its appearance and its share of the page's re-editing record. The import
        // wrote 2.8 KB a stroke before the fix, and 5.4 KB with the copies once its pages were read back.
        XCTAssertLessThan(bytesPerStroke, 3_000)
        let document = try XCTUnwrap(PDFDocument(url: destination))
        XCTAssertEqual(document.pageCount, 2)
        for pageIndex in 0..<2 {
            XCTAssertEqual(PDFInkGroups.editableGroup(on: try XCTUnwrap(document.page(at: pageIndex)))?.record.strokeNames.count, 1_000)
        }
    }

    /// A save of a PDF read from a file, as every save in Graphite is, writes new strokes as compactly, and draws them as
    /// PDFKit wrote them: the markup copy and the profiles' copies are all compaction removes.
    func testStrokesSavedIntoAFileReadBackDrawAsWrittenWithoutTheirCopies() throws {
        let vault = try TemporaryVault.make(prefix: "DenseInkWriting", for: self)
        let blankLocation = vault.location(of: "Blank.pdf")
        try DenseHandwritingNotebook.blankPages(count: 1, size: DenseHandwritingNotebook.pageSize).write(to: blankLocation)
        let document = try XCTUnwrap(PDFDocument(url: blankLocation))
        PDFPageManager.prepareForWriting(document)
        let page = try XCTUnwrap(document.page(at: 0))
        let coordinates = try PageCoordinates(cropBox: page.bounds(for: .cropBox), overlaySize: DenseHandwritingNotebook.pageSize)
        var tracker = PDFPageInkTracker(group: PDFInkGroups.newGroup(on: page))
        let update = tracker.update(for: DenseHandwritingNotebook.drawing(strokeCount: 300), pageIndex: 0, coordinates: coordinates)
        try PDFPageManager.apply(.updateInk(update), to: document, drawsInkOutlines: true)
        let uncompactedLocation = vault.location(of: "Uncompacted.pdf")
        XCTAssertTrue(document.write(to: uncompactedLocation))
        let uncompactedBytes = try Data(contentsOf: uncompactedLocation)
        XCTAssertNotNil(uncompactedBytes.range(of: Data("AAPL:AKExtras".utf8)), "PDFKit writes its markup copy into a document read from a file.")
        XCTAssertGreaterThan(Self.colorProfileObjectCount(in: uncompactedBytes), 100, "and a colour profile for each appearance.")

        let compacted = try XCTUnwrap(PDFObjectCompaction.compacted(uncompactedBytes))
        XCTAssertEqual(compacted.report.inkMarkupCopiesRemoved, 300)
        XCTAssertGreaterThan(compacted.report.colorProfileCopiesShared, 100)
        XCTAssertNil(compacted.data.range(of: Data("AAPL:AKExtras".utf8)))
        XCTAssertEqual(Self.colorProfileObjectCount(in: compacted.data), 1)
        print("DenseInkWritingTests compaction: \(uncompactedBytes.count) bytes to \(compacted.data.count) for 300 strokes")
        XCTAssertLessThan(compacted.data.count * 2, uncompactedBytes.count, "Less than half the room.")

        let reopened = try XCTUnwrap(PDFDocument(data: compacted.data))
        let reopenedPage = try XCTUnwrap(reopened.page(at: 0))
        let names = Set(reopenedPage.annotations.compactMap(\.persistentName))
        XCTAssertEqual(names, Set(update.addedStrokes.compactMap(\.name)), "Every stroke keeps the name edits find it by.")
        XCTAssertNotNil(PDFInkGroups.editableGroup(on: reopenedPage))
        let original = try XCTUnwrap(PDFDocument(url: uncompactedLocation)?.page(at: 0))
        XCTAssertEqual(try Self.drawnPixels(of: reopenedPage), try Self.drawnPixels(of: original), "Drawn exactly as PDFKit wrote it.")
    }

    /// The objects of the file that are colour profiles: a stream with three components and an RGB alternate.
    private static func colorProfileObjectCount(in fileBytes: Data) -> Int {
        let text = String(decoding: fileBytes, as: UTF8.self)
        return text.components(separatedBy: "/Alternate /DeviceRGB").count - 1
    }

    /// The page drawn with its annotations at two pixels a point, as grey levels.
    private static func drawnPixels(of page: PDFPage) throws -> [UInt8] {
        let bounds = page.bounds(for: .mediaBox)
        let width = Int(bounds.width * 2), height = Int(bounds.height * 2)
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                              space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue))
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: 2, y: 2)
        page.draw(with: .mediaBox, to: context)
        let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        return Array(UnsafeBufferPointer(start: pixels, count: width * height))
    }
}
