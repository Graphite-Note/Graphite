/**
 * File: PDFPagePictures.swift
 * ---------------------------
 * Layer: Tests
 * Description: Draws the pages of a PDF as PNG files, with their annotations, for a person to look at.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

import Foundation
import CoreGraphics
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// Draws the pages of a PDF as PNG pictures, annotations included, as PDFKit draws them for every reader, so a test can
/// leave a picture of what it wrote for a person to look at (an import compared with the source app's own export, for
/// example). The pictures go where the caller says, never into the repository.
public enum PDFPagePictures {
    /// 144 pixels per inch: twice the page's points, sharp enough to read small text.
    public static let pixelsPerPoint = 2.0

    /// Writes "<name> page <n>.png" for each page into `folder`, made if it is missing; returns the files written.
    @discardableResult
    public static func write(_ document: PDFDocument, named name: String, into folder: URL) throws -> [URL] {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var written: [URL] = []
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex), let picture = picture(of: page) else { continue }
            let location = folder.appendingPathComponent("\(name) page \(pageIndex + 1).png")
            guard let destination = CGImageDestinationCreateWithURL(location as CFURL, UTType.png.identifier as CFString, 1, nil) else { continue }
            CGImageDestinationAddImage(destination, picture, nil)
            if CGImageDestinationFinalize(destination) { written.append(location) }
        }
        return written
    }

    /// The page on white, its crop box at `pixelsPerPoint`.
    public static func picture(of page: PDFPage) -> CGImage? {
        let box = page.bounds(for: .cropBox)
        let width = Int((box.width * pixelsPerPoint).rounded()), height = Int((box.height * pixelsPerPoint).rounded())
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: pixelsPerPoint, y: pixelsPerPoint)
        page.draw(with: .cropBox, to: context)
        return context.makeImage()
    }
}
