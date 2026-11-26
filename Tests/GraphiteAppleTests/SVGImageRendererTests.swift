/**
 * File: SVGImageRendererTests.swift
 * ---------------------------------
 * Layer: Tests
 * Description: SVG files Graphite did not write are shown (HUNT-375): a schematic of text, lines and circles, a small
 *              icon drawn at the width it is shown, a Graphite drawing another app changed, and a file that is not SVG.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */
import XCTest
import CoreGraphics
import GraphiteCore
import GraphiteTestSupport
@testable import GraphiteApple

final class SVGImageRendererTests: XCTestCase {
    private let standardColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    /// Shaped like the schematic embedded on 2026-11-23: a white frame, wires as
    /// polylines, an inverter's triangle and bubble, labels in a serif font with empty `style`
    /// attributes, and a content-credentials manifest in its metadata.
    private let schematic = """
    <svg xmlns="http://www.w3.org/2000/svg" width="980" height="470" viewBox="0 0 980 470" xmlns:c2pa="http://c2pa.org/manifest">\
    <rect x="10" y="10" width="960" height="450" rx="14" fill="white" stroke="black" stroke-width="1.4"/>\
    <path d="M10,48 L970,48" stroke="black" stroke-width="1.4"/>\
    <text x="490.0" y="30" font-family="Latin Modern Roman, CMU Serif, serif" font-size="17" text-anchor="middle" dominant-baseline="central" style="">ADDF_X1_A8TR</text>\
    <polyline points="46,110 80,110" fill="none" stroke="black" stroke-width="1.4"/>\
    <polygon points="80,96 80,124 114,110" fill="white" stroke="black" stroke-width="1.4"/>\
    <circle cx="119" cy="110" r="5" fill="white" stroke="black" stroke-width="1.4"/>\
    <polyline points="124,300 900,300" fill="none" stroke="black" stroke-width="8"/>\
    <metadata><c2pa:manifest>AAAAAAAAAAAAAAAA</c2pa:manifest></metadata></svg>
    """

    func testAnSVGFromAnotherAppIsDrawnAtTheWidthItIsShown() async throws {
        let location = try write(Data(schematic.utf8), named: "Derived schematic.svg")
        let image = try await ImageFileService().displayImage(at: location, limit: PreviewPixelLimit(maximumPixelDimension: 2_000, displayPixelWidth: 490))
        XCTAssertEqual(image.width, 490)
        XCTAssertEqual(image.height, 235)
        let pixelBytes = try pixels(of: image)
        // The thick wire at y = 300 is at row 150 at half scale; above it is the frame's white inside.
        XCTAssertLessThan(pixel(pixelBytes, width: image.width, column: 250, row: 150)[0], 60, "The wire is drawn.")
        XCTAssertEqual(pixel(pixelBytes, width: image.width, column: 250, row: 130), [255, 255, 255, 255], "The frame is filled white.")
        // Outside the frame's rounded corner the SVG draws nothing, so the image is transparent there.
        XCTAssertEqual(pixel(pixelBytes, width: image.width, column: 1, row: 1)[3], 0)
        let titleRows = 8..<22, titleColumns = 200..<290
        let darkTitlePixels = titleRows.flatMap { row in titleColumns.map { column in pixel(pixelBytes, width: image.width, column: column, row: row)[0] } }
            .filter { red in red < 128 }
        XCTAssertGreaterThan(darkTitlePixels.count, 30, "The title's text is drawn.")
    }

    func testASmallIconIsDrawnSharpAtTheWidthItIsShown() async throws {
        let icon = ##"<svg xmlns="http://www.w3.org/2000/svg" width="24" height="12"><rect x="0" y="0" width="12" height="12" fill="#ff0000"/></svg>"##
        let location = try write(Data(icon.utf8), named: "Icon.svg")
        let image = try await ImageFileService().displayImage(at: location, limit: PreviewPixelLimit(maximumPixelDimension: 2_000, displayPixelWidth: 600))
        XCTAssertEqual(image.width, 600)
        XCTAssertEqual(image.height, 300)
        let pixelBytes = try pixels(of: image)
        XCTAssertEqual(pixel(pixelBytes, width: image.width, column: 299, row: 150), [255, 0, 0, 255])
        XCTAssertEqual(pixel(pixelBytes, width: image.width, column: 301, row: 150)[3], 0)
    }

    func testAGraphiteDrawingChangedInAnotherAppIsStillShown() async throws {
        let drawing = VectorDrawing(size: CGSize(width: 400, height: 200), background: .white, shapes: [])
        let payload = DrawingPayload(width: 400, height: 200, background: .white, strokes: Data("pencil strokes".utf8))
        let written = try XCTUnwrap(String(data: SVGDrawingFile.encode(drawing, payload: payload), encoding: .utf8))
        let changed = written.replacingOccurrences(of: "</svg>", with: ##"<circle cx="200" cy="100" r="40" fill="#0000ff"/></svg>"##)
        XCTAssertNil(SVGDrawingFile.readMetadata(Data(changed.utf8)).payload, "Another app's change voids the drawing's record.")
        let location = try write(Data(changed.utf8), named: "Drawing.svg")
        let image = try await ImageFileService().displayImage(at: location, maximumPixelDimension: 400)
        XCTAssertEqual(image.width, 400)
        XCTAssertEqual(image.height, 200)
        XCTAssertEqual(pixel(try pixels(of: image), width: image.width, column: 200, row: 100), [0, 0, 255, 255], "The other app's circle is drawn.")
    }

    func testAFileThatIsNotSVGStillCannotBeShown() async throws {
        let location = try write(Data("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"10\"".utf8), named: "Broken.svg")
        do {
            _ = try await ImageFileService().displayImage(at: location, maximumPixelDimension: 400)
            XCTFail("A file that is not SVG has no image.")
        } catch {
            XCTAssertEqual(error as? SVGImageRenderingError, .unreadable)
        }
    }

    // MARK: Helpers

    private func write(_ fileData: Data, named name: String) throws -> URL {
        let directory = try TemporaryVault.make(prefix: "SVGImageRendererTests", for: self).root
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let location = directory.appendingPathComponent(name)
        try fileData.write(to: location)
        return location
    }

    /// Premultiplied sRGB RGBA bytes of an image, top row first.
    private func pixels(of image: CGImage) throws -> [UInt8] {
        var pixelBytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try pixelBytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                                  space: standardColorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return pixelBytes
    }

    private func pixel(_ pixelBytes: [UInt8], width: Int, column: Int, row: Int) -> [Int] {
        let offset = (row * width + column) * 4
        return (0..<4).map { component in Int(pixelBytes[offset + component]) }
    }
}
