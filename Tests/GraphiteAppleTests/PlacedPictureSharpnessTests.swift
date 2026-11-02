/**
 * File: PlacedPictureSharpnessTests.swift
 * ---------------------------------------
 * Layer: Tests
 * Description: A picture placed on a PDF page keeps its own pixels and its own file, and what
 *              that costs the PDF stays bounded.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */
import XCTest
import CoreGraphics
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import GraphiteCore
@testable import GraphiteApple
import GraphiteTestSupport

final class PlacedPictureSharpnessTests: XCTestCase {
    /// Varied blocks of color, so a JPEG's size is that of a photograph's rather than nothing.
    private static func bitmap(width: Int, height: Int, hasAlpha: Bool = false, blockSide: Int = 16) throws -> CGImage {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let alphaInfo = hasAlpha ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: alphaInfo.rawValue))
        var state: UInt32 = 54_321
        for row in stride(from: 0, to: height, by: blockSide) {
            for column in stride(from: 0, to: width, by: blockSide) {
                state = state &* 1_664_525 &+ 1_013_904_223
                context.setFillColor(CGColor(srgbRed: CGFloat(state >> 24 & 0xFF) / 255, green: CGFloat(state >> 16 & 0xFF) / 255, blue: CGFloat(state >> 8 & 0xFF) / 255, alpha: 1))
                context.fill(CGRect(x: column, y: row, width: blockSide, height: blockSide))
            }
        }
        return try XCTUnwrap(context.makeImage())
    }

    private static func encoded(_ image: CGImage, as type: UTType, quality: Double? = nil, orientation: Int? = nil) throws -> Data {
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil))
        var options: [CFString: Any] = [:]
        if let quality { options[kCGImageDestinationLossyCompressionQuality] = quality }
        if let orientation { options[kCGImagePropertyOrientation] = orientation }
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    /// The owner's case: a 4032 by 3024 photo became 715 by 536.
    func testATwelveMegapixelPhotoKeepsEveryPixelAndItsOwnFile() throws {
        let photo = try Self.encoded(try Self.bitmap(width: 4_032, height: 3_024), as: .jpeg, quality: 0.8)
        let prepared = try DrawingPictures.pagePicture(from: photo)
        XCTAssertEqual(prepared.pixelSize, CGSize(width: 4_032, height: 3_024))
        XCTAssertEqual(prepared.imageData, photo, "The very file: it is not encoded again.")
    }

    func testAnOpaqueScreenshotStaysThePNGItIs() throws {
        let screenshot = try Self.encoded(try Self.bitmap(width: 600, height: 400), as: .png)
        let prepared = try DrawingPictures.pagePicture(from: screenshot)
        XCTAssertEqual(prepared.imageData, screenshot, "No JPEG smudges its text.")
    }

    func testAPictureWithAnOrientationIsTurnedOnceAndKeepsItsPixels() throws {
        let turned = try Self.encoded(try Self.bitmap(width: 800, height: 400), as: .jpeg, quality: 0.8, orientation: 6)
        let prepared = try DrawingPictures.pagePicture(from: turned)
        XCTAssertEqual(prepared.pixelSize, CGSize(width: 400, height: 800))
        XCTAssertTrue(prepared.imageData.starts(with: [0xFF, 0xD8]))
    }

    func testOnlyAPictureOverThePagesBoundsIsReducedAndAsLittleAsFits() throws {
        let tooManyPixels = try Self.encoded(try Self.bitmap(width: 6_000, height: 5_000, blockSide: 512), as: .jpeg, quality: 0.3)
        let prepared = try DrawingPictures.pagePicture(from: tooManyPixels)
        let keptPixels = prepared.pixelSize.width * prepared.pixelSize.height
        XCTAssertLessThanOrEqual(keptPixels, CGFloat(DrawingPictures.maximumPagePicturePixelCount) * 1.01)
        XCTAssertGreaterThan(keptPixels, CGFloat(DrawingPictures.maximumPagePicturePixelCount) * 0.95, "No more is taken than the bound asks.")
        XCTAssertLessThanOrEqual(prepared.imageData.count, PDFPicture.maximumImageBytes)
    }

    /// A picture whose bytes stay over the bound at the bound's pixels goes on reducing until it fits.
    func testAPictureWhoseBytesStayOverTheBoundKeepsReducingUntilItFits() throws {
        let busy = try Self.encoded(try Self.bitmap(width: 6_000, height: 5_000, blockSide: 4), as: .jpeg, quality: 0.3)
        let prepared = try DrawingPictures.pagePicture(from: busy)
        XCTAssertLessThanOrEqual(prepared.imageData.count, PDFPicture.maximumImageBytes)
        XCTAssertEqual(prepared.pixelSize.width / prepared.pixelSize.height, 1.2, accuracy: 0.01, "Its proportions stay.")
    }

    func testWhatIsNotAnImageIsRefused() {
        XCTAssertThrowsError(try DrawingPictures.pagePicture(from: Data("not an image".utf8)))
    }

    /// The PDF keeps the photo at about its own size twice, as the appearance other readers
    /// show (the JPEG itself, `PDFObjectCompaction`) and for moving it, not as inflated pixels.
    func testASavedPDFHoldsTheFullPhotoAtAboutTwiceItsBytesAndOtherReadersGetEveryPixel() async throws {
        let vault = try TemporaryVault(prefix: "PlacedPicture")
        defer { vault.remove() }
        let location = vault.location(of: "Notebook.pdf")
        let revision = try await PDFFileService().create(documentData: PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .blank), pageCount: 1), at: location)
        let emptySize = try XCTUnwrap(try FileManager.default.attributesOfItem(atPath: location.path)[.size] as? Int)
        let photo = try Self.encoded(try Self.bitmap(width: 4_032, height: 3_024), as: .jpeg, quality: 0.8)
        let picture = PDFPicture(imageData: try DrawingPictures.pagePicture(from: photo).imageData, bounds: CGRect(x: 100, y: 300, width: 357, height: 268), quarterTurns: 0)
        _ = try await PDFFileService().save(url: location, revision: revision, edits: [.addPicture(page: 0, picture: picture)])
        let savedBytes = try Data(contentsOf: location)
        XCTAssertLessThan(savedBytes.count - emptySize, photo.count * 5 / 2, "The photo costs about twice its bytes.")
        XCTAssertNotNil(savedBytes.range(of: photo), "The appearance is the photo's own JPEG, at its full size.")
    }

    /// Zoomed out, a page draws from far fewer pixels than the picture has, and takes the
    /// memory of far fewer; zoomed in it has them all. An appearance always has them all.
    func testAnOrdinaryZoomDrawsFromTheReducedImageAndADeepZoomFromThePicturesOwn() throws {
        let photo = try Self.encoded(try Self.bitmap(width: 4_032, height: 3_024), as: .jpeg, quality: 0.8)
        let image = try XCTUnwrap(PDFPicture.decodedImage(photo))
        let shown = PDFPictureAnnotationDrawing(image: image, imageData: photo, pictureSize: CGSize(width: 357, height: 268), quarterTurns: 0, rotationRadians: 0, drawsAppearance: false)
        let longestReduced = PDFPictureAnnotationDrawing.reducedImageLongestSide
        XCTAssertEqual(max(shown.image(forLongestDrawnPixels: 714).width, shown.image(forLongestDrawnPixels: 714).height), longestReduced)
        XCTAssertEqual(shown.image(forLongestDrawnPixels: CGFloat(longestReduced) + 1).width, 4_032)
        let written = PDFPictureAnnotationDrawing(image: image, imageData: photo, pictureSize: CGSize(width: 357, height: 268), quarterTurns: 0, rotationRadians: 0, drawsAppearance: true)
        XCTAssertEqual(written.image(forLongestDrawnPixels: 357).width, 4_032)
    }

    /// Rotate Right on a drawing's picture encodes a JPEG again: four turns stay close to the start.
    func testFourTurnsOfADrawingsPhotoStayCloseToTheStart() throws {
        let start = try Self.encoded(try Self.bitmap(width: 320, height: 240), as: .jpeg, quality: 0.9)
        var turned = start
        for _ in 0..<4 { turned = try PictureEditing.rotatedClockwise(turned) }
        func pixels(_ data: Data) throws -> [UInt8] {
            let image = try XCTUnwrap(PDFPicture.decodedImage(data))
            var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
            let context = try XCTUnwrap(CGContext(data: &bytes, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                                  space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return bytes
        }
        let startPixels = try pixels(start), turnedPixels = try pixels(turned)
        XCTAssertEqual(startPixels.count, turnedPixels.count)
        let averageDifference = zip(startPixels, turnedPixels).reduce(0.0) { sum, pair in sum + abs(Double(pair.0) - Double(pair.1)) } / Double(startPixels.count)
        XCTAssertLessThan(averageDifference, 2.5, "Levels out of 255, on average.")
    }
}
