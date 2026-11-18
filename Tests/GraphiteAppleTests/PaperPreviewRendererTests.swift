/**
 * File: PaperPreviewRendererTests.swift
 * -------------------------------------
 * Layer: Tests
 * Description: The pictures of paper the New Notebook sheet shows, and the library thumbnail of a dotted notebook.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 18/11/2026
 */

import XCTest
import CoreGraphics
import PDFKit
import GraphiteCore
@testable import GraphiteApple

final class PaperPreviewRendererTests: XCTestCase {
    func testPictureKeepsThePagesProportions() throws {
        let landscape = PaperSpecification(template: .dotted).sized(NotebookPageSize.a4.pointSize(in: .landscape))
        let image = try PaperPreviewRenderer.image(of: landscape, longerSidePixels: 200)
        XCTAssertEqual(image.width, 200)
        XCTAssertEqual(image.height, 141)
    }

    /// The sheet's picture of a paper is the first page of the notebook the sheet then makes, pixel for pixel: the notebook's
    /// PDF, several pages long, drawn at the picture's size gives the same pixels as the picture.
    func testThePictureOfAPaperIsTheFirstPageOfTheNotebookMade() throws {
        let choices: [NewNotebookOptions] = [
            NewNotebookOptions(paperChoice: .ruledNarrow, paperStyle: PaperSpecification(template: .blank), pageSize: .named(.a4, .portrait), pageCount: 4),
            NewNotebookOptions(paperChoice: .ruledNarrow, paperStyle: PaperSpecification(template: .dotted), pageSize: .named(.a5, .landscape), pageCount: 3),
        ]
        for options in choices {
            let picture = try PaperPreviewRenderer.image(of: options.paper, longerSidePixels: 400)
            let notebookData = try NewNotebookDocument.data(for: options, titled: "Lecture", templateLocation: nil)
            let notebook = try XCTUnwrap(CGPDFDocument(try XCTUnwrap(CGDataProvider(data: notebookData as CFData))))
            XCTAssertEqual(notebook.numberOfPages, options.pageCount)
            let firstPage = try drawn(try XCTUnwrap(notebook.page(at: 1)), width: picture.width, height: picture.height)
            XCTAssertEqual(rgbaBytes(of: firstPage), rgbaBytes(of: picture), "\(options.paper)")
        }
    }

    private func drawn(_ page: CGPDFPage, width: Int, height: Int) throws -> CGImage {
        let pageBox = page.getBoxRect(.mediaBox)
        let scale = Double(max(width, height)) / max(pageBox.width, pageBox.height)
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.interpolationQuality = .high
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -pageBox.minX, y: -pageBox.minY)
        context.drawPDFPage(page)
        return try XCTUnwrap(context.makeImage())
    }

    private func rgbaBytes(of image: CGImage) -> Data? {
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.data.map { data in Data(bytes: data, count: image.width * image.height * 4) }
    }

    func testPictureSizeIsBounded() throws {
        let image = try PaperPreviewRenderer.image(of: PaperSpecification(template: .blank), longerSidePixels: 50_000)
        XCTAssertEqual(max(image.width, image.height), PaperPreviewRenderer.maximumSidePixels)
    }

    func testBlankPaperIsOneColorAndRuledPaperIsNot() throws {
        XCTAssertEqual(try distinctColorCount(of: PaperSpecification(template: .blank)), 1)
        XCTAssertGreaterThan(try distinctColorCount(of: PaperSpecification(template: .ruled)), 1)
    }

    /// HUNT-212: a dotted notebook's picture was a plain white page, without its dots.
    func testDottedPaperShowsItsDotsAtTheSizesTheSheetAndTheLibraryDrawThem() throws {
        for longerSidePixels in [320, 640] {
            XCTAssertGreaterThan(try distinctColorCount(of: PaperSpecification(template: .dotted), longerSidePixels: longerSidePixels), 1, "\(longerSidePixels) pixels")
        }
    }

    /// HUNT-212: the library tile of a dotted notebook, made by PDFKit from the saved PDF, showed no dots either.
    func testTheLibraryThumbnailOfADottedNotebookShowsItsDots() throws {
        let data = try PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .dotted), pageCount: 1)
        let page = try XCTUnwrap(PDFDocument(data: data)?.page(at: 0))
        let thumbnail = try XCTUnwrap(LibraryPreviewLoader.thumbnail(of: page, longerSidePixels: 540))
        let bytes = try pixels(of: thumbnail)
        var colors = Set<UInt32>()
        for pixelStart in stride(from: 0, to: bytes.count, by: 4) {
            colors.insert(UInt32(bytes[pixelStart]) << 16 | UInt32(bytes[pixelStart + 1]) << 8 | UInt32(bytes[pixelStart + 2]))
        }
        XCTAssertGreaterThan(colors.count, 1)
    }

    /// HUNT-212, seen 2026-11-12 in the iPad simulator: the tile of a new dotted notebook looked blank. Its dots are
    /// there in the thumbnail, but they must be dark enough to be seen: the darkest pixel at least a tenth darker
    /// than the paper.
    func testTheLibraryThumbnailOfADottedNotebookShowsItsDotsDarkEnoughToSee() throws {
        let data = try PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .dotted), pageCount: 1)
        let page = try XCTUnwrap(PDFDocument(data: data)?.page(at: 0))
        let thumbnail = try XCTUnwrap(LibraryPreviewLoader.thumbnail(of: page, longerSidePixels: 540))
        let bytes = try pixels(of: thumbnail)
        var darkest = 255, lightest = 0
        for pixelStart in stride(from: 0, to: bytes.count, by: 4) {
            let gray = (Int(bytes[pixelStart]) + Int(bytes[pixelStart + 1]) + Int(bytes[pixelStart + 2])) / 3
            darkest = min(darkest, gray)
            lightest = max(lightest, gray)
        }
        XCTAssertLessThanOrEqual(darkest, lightest * 9 / 10, "The darkest pixel \(darkest) against the paper's \(lightest)")
    }

    func testPaperColorIsDrawn() throws {
        let ivory = PaperSpecification(template: .blank, paperColorHex: "#fbf7ea")
        let pixel = try cornerPixel(of: try PaperPreviewRenderer.image(of: ivory, longerSidePixels: 64))
        XCTAssertEqual(pixel.red, 0xfb, accuracy: 2)
        XCTAssertEqual(pixel.green, 0xf7, accuracy: 2)
        XCTAssertEqual(pixel.blue, 0xea, accuracy: 2)
    }

    func testAnInvalidPaperIsAnErrorNotAPicture() {
        let tooSmall = PaperSpecification(template: .blank).sized(CGSize(width: 10, height: 10))
        XCTAssertThrowsError(try PaperPreviewRenderer.image(of: tooSmall, longerSidePixels: 64))
    }

    private func pixels(of image: CGImage) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try XCTUnwrap(CGContext(data: &bytes, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return bytes
    }

    private func distinctColorCount(of paper: PaperSpecification, longerSidePixels: Int = 256) throws -> Int {
        let bytes = try pixels(of: try PaperPreviewRenderer.image(of: paper, longerSidePixels: longerSidePixels))
        var colors = Set<UInt32>()
        for pixelStart in stride(from: 0, to: bytes.count, by: 4) {
            colors.insert(UInt32(bytes[pixelStart]) << 16 | UInt32(bytes[pixelStart + 1]) << 8 | UInt32(bytes[pixelStart + 2]))
        }
        return colors.count
    }

    private func cornerPixel(of image: CGImage) throws -> (red: Double, green: Double, blue: Double) {
        let bytes = try pixels(of: image)
        return (Double(bytes[0]), Double(bytes[1]), Double(bytes[2]))
    }
}
