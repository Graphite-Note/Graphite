/**
 * File: PDFPictureEditingTests.swift
 * ----------------------------------
 * Layer: Tests
 * Description: Turning, cropping and ordering pictures on PDF pages through the session: each is one
 *              step of the PDF's history, and the saved file shows the result.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 02/11/2026
 */
import XCTest
import PDFKit
import ImageIO
import GraphiteCore
import GraphiteApple
@testable import GraphiteUI
import GraphiteTestSupport

/// Turning, cropping and ordering pictures on PDF pages through the session: each is one
/// step of the PDF's history, and the saved file shows the result.
@MainActor
final class PDFPictureEditingTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = try TemporaryVault.make(prefix: "PDFPictureEditing", for: self).root
    }

    private func openSession(pageRotation: Int = 0) async throws -> (PDFSession, URL) {
        let location = directory.appendingPathComponent("Notebook-\(UUID().uuidString).pdf")
        var mediaBox = CGRect(x: 0, y: 0, width: 400, height: 600)
        let context = try XCTUnwrap(CGContext(location as CFURL, mediaBox: &mediaBox, nil))
        context.beginPDFPage(nil)
        context.endPDFPage()
        context.closePDF()
        if pageRotation != 0 {
            let document = try XCTUnwrap(PDFDocument(url: location))
            try XCTUnwrap(document.page(at: 0)).rotation = pageRotation
            XCTAssertTrue(document.write(to: location))
        }
        let session = try await PDFSession.open(location)
        session.undoManager.groupsByEvent = false
        return (session, location)
    }

    private func step(in session: PDFSession, _ operation: () async throws -> Void) async rethrows {
        session.undoManager.beginUndoGrouping()
        defer { session.undoManager.endUndoGrouping() }
        try await operation()
    }

    /// Red on the left half, blue on the right, so the orientation shows.
    private func twoColorImageData(width: Int = 200, height: Int = 100) throws -> Data {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: width / 2, y: 0, width: width / 2, height: height))
        return try ImageEncoding.pngData(from: try XCTUnwrap(context.makeImage()))
    }

    /// Whether a picture's own image is mostly red, mostly blue, or both.
    private func colors(of imageData: Data) throws -> Set<String> {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(imageData as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try XCTUnwrap(CGContext(data: &pixels, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                              space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        var seen: Set<String> = []
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            if pixels[offset] > 200, pixels[offset + 2] < 60 { seen.insert("red") }
            if pixels[offset + 2] > 200, pixels[offset] < 60 { seen.insert("blue") }
        }
        return seen
    }

    func testTurningAPictureSwapsItsSidesAboutItsMiddleAsOneStep() async throws {
        let (session, location) = try await openSession()
        try await step(in: session) { try await session.addPicture(imageData: try twoColorImageData()) }
        let page = try XCTUnwrap(session.document.page(at: 0))
        let placed = try XCTUnwrap(session.pictures(on: page).first)
        let selection = try XCTUnwrap(session.selectedPicture)

        try await step(in: session) { try await session.rotatePictureRight(selection) }
        let turned = try XCTUnwrap(session.pictures(on: page).first)
        XCTAssertEqual(turned.name, placed.name)
        XCTAssertEqual(turned.bounds.width, placed.bounds.height, accuracy: 0.01)
        XCTAssertEqual(turned.bounds.height, placed.bounds.width, accuracy: 0.01)
        XCTAssertEqual(turned.bounds.midX, placed.bounds.midX, accuracy: 0.01)
        XCTAssertEqual(turned.bounds.midY, placed.bounds.midY, accuracy: 0.01)
        XCTAssertEqual(turned.imageData, placed.imageData, "Turning keeps every byte of the picture")
        XCTAssertNotEqual(turned.quarterTurns, placed.quarterTurns)
        XCTAssertEqual(session.undoAvailability.undoActionName, "Rotate Image Right")

        session.undoAvailability.undo()
        XCTAssertEqual(session.pictures(on: page), [placed])
        session.undoAvailability.redo()
        XCTAssertEqual(session.pictures(on: page), [turned])
        try await session.save()
        XCTAssertEqual(PDFPageManager.pictures(on: try XCTUnwrap(PDFDocument(url: location)?.page(at: 0))), [turned])
    }

    /// Rotate Right on a page draws the picture a quarter turn further and never encodes it again
    /// (HUNT-018): a JPEG's bytes after four turns are its bytes before them, also in the saved file.
    func testFourTurnsRightKeepEveryByteOfAJPEGAndItsPlaceInTheSavedFile() async throws {
        let (session, location) = try await openSession()
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(XCTUnwrap(CGImageSourceCreateWithData(try twoColorImageData() as CFData, nil)), 0, nil))
        let jpeg = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(jpeg, "public.jpeg" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let jpegBytes = jpeg as Data
        try await step(in: session) { try await session.addPicture(imageData: jpegBytes) }
        let page = try XCTUnwrap(session.document.page(at: 0))
        let placed = try XCTUnwrap(session.pictures(on: page).first)
        XCTAssertEqual(placed.imageData, jpegBytes, "An upright JPEG is placed as the very file")
        let selection = try XCTUnwrap(session.selectedPicture)
        for turn in 1...4 {
            try await step(in: session) { try session.rotatePictureRight(selection) }
            let turned = try XCTUnwrap(session.pictures(on: page).first)
            XCTAssertEqual(turned.imageData, jpegBytes, "Turn \(turn) encodes nothing again")
            XCTAssertEqual(turned.bounds.midX, placed.bounds.midX, accuracy: 0.01, "Turn \(turn)")
            XCTAssertEqual(turned.bounds.midY, placed.bounds.midY, accuracy: 0.01, "Turn \(turn)")
        }
        let turnedFourTimes = try XCTUnwrap(session.pictures(on: page).first)
        XCTAssertEqual(turnedFourTimes.bounds.width, placed.bounds.width, accuracy: 0.01, "A full turn is the place it started")
        XCTAssertEqual(turnedFourTimes.bounds.height, placed.bounds.height, accuracy: 0.01)
        XCTAssertEqual(turnedFourTimes.quarterTurns.quotientAndRemainder(dividingBy: 4).remainder, 0)
        try await session.save()
        let saved = try XCTUnwrap(PDFPageManager.pictures(on: try XCTUnwrap(PDFDocument(url: location)?.page(at: 0))).first)
        XCTAssertEqual(saved.imageData, jpegBytes, "The file holds the same bytes")
    }

    func testACropKeepsThePartShownInsideItAlsoOnATurnedPage() async throws {
        for pageRotation in [0, 90] {
            let (session, location) = try await openSession(pageRotation: pageRotation)
            try await step(in: session) { try await session.addPicture(imageData: try twoColorImageData()) }
            let page = try XCTUnwrap(session.document.page(at: 0))
            let placed = try XCTUnwrap(session.pictures(on: page).first)
            let selection = try XCTUnwrap(session.selectedPicture)
            XCTAssertEqual(try colors(of: placed.imageData), ["red", "blue"])

            // The half of the picture where its red side is shown: its left as the page is
            // read, which on a page turned clockwise is the bottom of the page's own box.
            let bounds = placed.bounds
            let redHalf = pageRotation == 0
                ? CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width / 2, height: bounds.height)
                : CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: bounds.height / 2)
            try await step(in: session) { try await session.cropPicture(selection, to: redHalf) }
            let cropped = try XCTUnwrap(session.pictures(on: page).first)
            XCTAssertEqual(cropped.bounds, redHalf, "Page turned \(pageRotation)°")
            XCTAssertEqual(try colors(of: cropped.imageData), ["red"], "Page turned \(pageRotation)°")
            XCTAssertEqual(session.undoAvailability.undoActionName, "Crop Image")

            // A crop that is the whole picture changes nothing, and is no step.
            try await session.cropPicture(selection, to: cropped.bounds.insetBy(dx: -20, dy: -20))
            XCTAssertEqual(session.pictures(on: page), [cropped])
            XCTAssertEqual(session.undoAvailability.undoActionName, "Crop Image")
            session.undoAvailability.undo()
            XCTAssertEqual(session.pictures(on: page), [placed])
            session.undoAvailability.redo()
            try await session.save()
            XCTAssertEqual(PDFPageManager.pictures(on: try XCTUnwrap(PDFDocument(url: location)?.page(at: 0))), [cropped])
        }
    }

    func testPicturesGoOverAndUnderEachOtherAndUndoPutsThemBack() async throws {
        let (session, _) = try await openSession()
        for _ in 0..<3 { try await step(in: session) { try await session.addPicture(imageData: try twoColorImageData()) } }
        let page = try XCTUnwrap(session.document.page(at: 0))
        let names = session.pictures(on: page).map(\.name)
        let middle = PDFPictureSelection(pictureName: names[1], page: session.historyPage(for: page))

        try await step(in: session) { try session.movePictureInOrder(middle, toFront: true) }
        XCTAssertEqual(session.pictures(on: page).map(\.name), [names[0], names[2], names[1]])
        XCTAssertEqual(session.undoAvailability.undoActionName, "Bring Image to Front")
        try await step(in: session) { try session.movePictureInOrder(middle, toFront: false) }
        XCTAssertEqual(session.pictures(on: page).map(\.name), [names[1], names[0], names[2]])
        // Already at the back: nothing changes, and no step is added.
        try session.movePictureInOrder(middle, toFront: false)
        XCTAssertEqual(session.undoAvailability.undoActionName, "Send Image to Back")

        session.undoAvailability.undo()
        XCTAssertEqual(session.pictures(on: page).map(\.name), [names[0], names[2], names[1]])
        session.undoAvailability.undo()
        XCTAssertEqual(session.pictures(on: page).map(\.name), names)
    }
}
