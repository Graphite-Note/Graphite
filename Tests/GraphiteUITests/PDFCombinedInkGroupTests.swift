/**
 * File: PDFCombinedInkGroupTests.swift
 * ------------------------------------
 * Layer: Tests
 * Description: A densely written page's ink group is shown as one annotation that draws all of its strokes as PDFKit
 *              draws them, upright and turned; erasing and writing on it, saving, exporting and duplicating the page
 *              keep one `/Ink` annotation per stroke in what is written.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 18/11/2026
 */
import XCTest
import PDFKit
import GraphiteCore
import GraphiteApple
import GraphiteTestSupport
@testable import GraphiteUI

@MainActor
final class PDFCombinedInkGroupTests: XCTestCase {
    private var vault: TemporaryVault!

    override func setUp() async throws {
        vault = try TemporaryVault.make(prefix: "PDFCombinedInkGroup", for: self)
    }

    func testADenseGroupIsShownAsOneAnnotationThatKnowsEveryStroke() async throws {
        let location = try await makeSavedPDF(strokeCount: 100)
        let session = try await PDFSession.open(location, combinesDenseInk: true)
        let page = try XCTUnwrap(session.document.page(at: 0))
        let ink = Self.inkAnnotations(on: page)
        XCTAssertEqual(ink.count, 1, "The shown page holds the group as one annotation.")
        let combinedGroup = try XCTUnwrap(ink.first?.combinedInkGroup)
        XCTAssertEqual(combinedGroup.strokes.map(\.name), Self.strokes(100).map(\.name))
        XCTAssertEqual(combinedGroup.group, PDFInkGroups.defaultGroup)
        XCTAssertNotEqual(PDFInkGroups.newGroup(on: page), PDFInkGroups.defaultGroup, "New ink does not go into the group the page holds combined.")
    }

    func testAFewStrokesStayOneAnnotationEach() async throws {
        let location = try await makeSavedPDF(strokeCount: PDFShownInkCombining.minimumStrokeCount - 1)
        let session = try await PDFSession.open(location, combinesDenseInk: true)
        let page = try XCTUnwrap(session.document.page(at: 0))
        XCTAssertEqual(Self.inkAnnotations(on: page).count, PDFShownInkCombining.minimumStrokeCount - 1)
        XCTAssertNil(Self.inkAnnotations(on: page).first?.combinedInkGroup)
    }

    func testTheGroupDrawsItsStrokesAsPDFKitDrawsThem() async throws {
        try await checkTheGroupDrawsItsStrokesAsPDFKitDrawsThem(rotation: 0)
    }

    func testATurnedPagesGroupDrawsItsStrokesAsPDFKitDrawsThem() async throws {
        try await checkTheGroupDrawsItsStrokesAsPDFKitDrawsThem(rotation: 90)
    }

    /// The page as the shown document draws it, its group's one annotation drawing the group's picture, against PDFKit's
    /// drawing of the page read from the file with every stroke an annotation of its own.
    private func checkTheGroupDrawsItsStrokesAsPDFKitDrawsThem(rotation: Int) async throws {
        let location = try await makeSavedPDF(strokeCount: 100, rotation: rotation)
        let session = try await PDFSession.open(location, combinesDenseInk: true)
        let page = try XCTUnwrap(session.document.page(at: 0))
        let combinedGroup = try XCTUnwrap(Self.inkAnnotations(on: page).first?.combinedInkGroup)
        let (width, height) = Self.pixelSize(of: page, width: 900)
        let picture = await PDFPageInkRenderer.picture(of: combinedGroup, on: page, pixelSize: CGSize(width: width, height: height), with: PDFPageInkRenderer())
        combinedGroup.show(try XCTUnwrap(picture))

        let shown = try Self.drawing(of: page, width: width, height: height)
        let reference = try Self.drawing(of: try XCTUnwrap(PDFDocument(url: location)?.page(at: 0)), width: width, height: height)
        let comparison = Self.compare(shown, reference)
        print("COMBINED-INK rotation \(rotation): \(comparison.inkPixels) ink pixels, \(comparison.differingPixels) differ, \(width)x\(height)")
        XCTAssertGreaterThan(comparison.inkPixels, 1_000)
        // Upright, no pixel differed on 2026-11-18; turned, 419 of 20,817 ink pixels did (2.0 %), the picture being drawn
        // from the copy of the file turned whole rather than stroke by stroke.
        let allowedShare = rotation == 0 ? 0.001 : 0.03
        XCTAssertLessThan(Double(comparison.differingPixels), Double(comparison.inkPixels) * allowedShare, "The group draws its strokes as PDFKit draws them.")
    }

    /// Erasing strokes of the group and writing new ones, then saving: the file holds one `/Ink` annotation per stroke
    /// left, as the export and a copy saved separately do, and the shown page still holds the group as one annotation.
    func testEditingAGroupKeepsOneInkAnnotationPerStrokeInWhatIsWritten() async throws {
        let location = try await makeSavedPDF(strokeCount: 100)
        let session = try await PDFSession.open(location, combinesDenseInk: true)
        let page = try XCTUnwrap(session.document.page(at: 0))
        let erased: Set<String> = ["stroke-0", "stroke-41", "stroke-99"]
        let added = (0..<2).map { index in
            PortableInkStroke(name: "added-\(index)", segments: [[CGPoint(x: 300, y: 300 + Double(index) * 20), CGPoint(x: 360, y: 340 + Double(index) * 20)]],
                              width: 4, red: 0, green: 0, blue: 0, alpha: 1, outline: nil)
        }
        try session.apply(.updateInk(PDFInkUpdate(pageIndex: 0, group: PDFInkGroups.defaultGroup, removal: .strokes(erased), addedStrokes: added, editableRecord: nil)))
        let combinedGroup = try XCTUnwrap(Self.inkAnnotations(on: page).first?.combinedInkGroup)
        XCTAssertEqual(combinedGroup.removedNames, erased)
        XCTAssertEqual(Self.inkAnnotations(on: page).count, 1 + added.count, "The group's one annotation and the two strokes written.")
        try await session.save()

        let expectedNames = Set(Self.strokes(100).compactMap(\.name)).subtracting(erased).union(added.compactMap(\.name))
        let saved = try XCTUnwrap(PDFDocument(url: location)?.page(at: 0))
        XCTAssertEqual(Set(Self.inkAnnotations(on: saved).compactMap(\.persistentName)), expectedNames)
        XCTAssertEqual(Self.inkAnnotations(on: saved).count, expectedNames.count, "One /Ink annotation per stroke in the file.")
        let exportedData = try await session.export(pages: [0])
        let exported = try XCTUnwrap(PDFDocument(data: exportedData)?.page(at: 0))
        XCTAssertEqual(Self.inkAnnotations(on: exported).count, expectedNames.count, "One /Ink annotation per stroke in the export.")
        let separateCopyLocation = try await session.saveSeparateCopy()
        let separateCopy = try XCTUnwrap(PDFDocument(url: separateCopyLocation)?.page(at: 0))
        XCTAssertEqual(Self.inkAnnotations(on: separateCopy).count, expectedNames.count, "One /Ink annotation per stroke in a copy shared.")
    }

    func testADuplicatedPageDrawsTheGroupToo() async throws {
        let location = try await makeSavedPDF(strokeCount: 100)
        let session = try await PDFSession.open(location, combinesDenseInk: true)
        try session.apply(.duplicate(page: 0))
        let duplicate = try XCTUnwrap(session.document.page(at: 1))
        let combinedGroup = try XCTUnwrap(Self.inkAnnotations(on: duplicate).first?.combinedInkGroup, "The duplicate's copy of the group's annotation draws the group.")
        XCTAssertEqual(combinedGroup.strokes.count, 100)
        try await session.save()
        XCTAssertEqual(Self.inkAnnotations(on: try XCTUnwrap(PDFDocument(url: location)?.page(at: 1))).count, 100)
    }

    // MARK: Making the PDF

    private static func strokes(_ count: Int) -> [PortableInkStroke] {
        (0..<count).map { index in
            let start = CGPoint(x: 40 + Double(index % 10) * 50, y: 120 + Double(index / 10) * 60)
            let outline = [[start, CGPoint(x: start.x + 4, y: start.y), CGPoint(x: start.x + 34, y: start.y + 40), CGPoint(x: start.x + 30, y: start.y + 40)]]
            return PortableInkStroke(name: "stroke-\(index)", segments: [[CGPoint(x: start.x + 2, y: start.y), CGPoint(x: start.x + 32, y: start.y + 40)]],
                                     width: 4, red: 0.2, green: 0.1, blue: 0.8, alpha: 1, outline: outline)
        }
    }

    private func makeSavedPDF(strokeCount: Int, rotation: Int = 0) async throws -> URL {
        let location = vault.location(of: "Dense\(strokeCount)-\(rotation).pdf")
        let revision = try await PDFFileService().create(documentData: PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .blank), pageCount: 1), at: location)
        var edits: [PDFEdit] = [.updateInk(PDFInkUpdate(pageIndex: 0, group: PDFInkGroups.defaultGroup, removal: .strokes([]),
                                                        addedStrokes: Self.strokes(strokeCount), editableRecord: nil))]
        if rotation != 0 { edits.append(.rotate(page: 0, clockwise: true)) }
        _ = try await PDFFileService().save(url: location, revision: revision, edits: edits)
        return location
    }

    private static func inkAnnotations(on page: PDFPage) -> [PDFAnnotation] {
        page.annotations.filter { annotation in annotation.value(forAnnotationKey: PDFPageManager.groupKey) != nil }
    }

    // MARK: Looking at the result

    private static func pixelSize(of page: PDFPage, width: Int) -> (Int, Int) {
        let cropBox = page.bounds(for: .cropBox)
        let turned = (page.rotation / 90) % 2 != 0
        let shown = turned ? CGSize(width: cropBox.height, height: cropBox.width) : cropBox.size
        return (width, Int((CGFloat(width) * shown.height / shown.width).rounded()))
    }

    /// The page drawn over white as PDFKit draws it, with its annotations.
    private static func drawing(of page: PDFPage, width: Int, height: Int) throws -> Bitmap {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                              space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let cropBox = page.bounds(for: .cropBox)
        let displayedWidth = (page.rotation / 90) % 2 != 0 ? cropBox.height : cropBox.width
        context.scaleBy(x: CGFloat(width) / displayedWidth, y: CGFloat(width) / displayedWidth)
        page.draw(with: .cropBox, to: context)
        return try Bitmap(context)
    }

    private struct Bitmap {
        let width: Int
        let bytes: [UInt8]

        init(_ context: CGContext) throws {
            width = context.width
            let data = try XCTUnwrap(context.data)
            bytes = Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: context.bytesPerRow * context.height))
        }

        func isInk(at offset: Int) -> Bool { bytes[offset] < 200 || bytes[offset + 1] < 200 || bytes[offset + 2] < 200 }
    }

    /// Ink pixels of the reference and pixels that differ by more than a sixth of full scale.
    private static func compare(_ shown: Bitmap, _ reference: Bitmap) -> (inkPixels: Int, differingPixels: Int) {
        var inkPixels = 0, differingPixels = 0
        for pixel in 0..<(reference.bytes.count / 4) {
            let offset = pixel * 4
            if reference.isInk(at: offset) { inkPixels += 1 }
            if (0..<3).contains(where: { channel in abs(Int(shown.bytes[offset + channel]) - Int(reference.bytes[offset + channel])) > 42 }) { differingPixels += 1 }
        }
        return (inkPixels, differingPixels)
    }
}
