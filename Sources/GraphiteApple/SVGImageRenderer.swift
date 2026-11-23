/**
 * File: SVGImageRenderer.swift
 * ----------------------------
 * Layer: Apple
 * Description: Draws an SVG file Graphite did not write (a diagram, a schematic, an icon) into pixels with SwiftDraw,
 *              for embeds, the reading view and the image pane, as Obsidian shows any SVG.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */
import Foundation
import CoreGraphics
import SwiftDraw

/// Apple's frameworks have no public SVG decoder (ImageIO reads none), so SVG files from other
/// applications are drawn by SwiftDraw: shapes, paths, text, transforms, gradients, clip paths,
/// masks and CSS styles, with pictures only from data URIs, never from a file or an address.
/// Graphite's own drawings keep `SVGDrawingFile`'s reader, which draws exactly what it wrote.
enum SVGImageRenderer {
    /// The SVG drawn as large as the place it is shown needs, on a transparent background as
    /// a browser shows it.
    static func image(fromFileData fileData: Data, limit: PreviewPixelLimit) throws -> CGImage {
        guard let picture = SVG(data: fileData) else {
            throw SVGImageRenderingError.unreadable
        }
        let width = Double(picture.size.width), height = Double(picture.size.height)
        guard width.isFinite, height.isFinite, width > 0, height > 0 else {
            throw SVGImageRenderingError.noSize
        }
        // Vector content is sharp at any scale, so a small icon shown across a column is drawn
        // at the column's pixels rather than magnified from its own few.
        let scale = Double(limit.longestPixelSide(forWidth: width, height: height)) / max(width, height)
        let pixelWidth = max(1, Int((width * scale).rounded())), pixelHeight = max(1, Int((height * scale).rounded()))
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw SVGImageRenderingError.cannotAllocatePixels
        }
        // SwiftDraw draws with SVG's origin at the top left, as UIKit's and AppKit's flipped contexts have it.
        context.translateBy(x: 0, y: Double(pixelHeight))
        context.scaleBy(x: 1, y: -1)
        context.draw(picture, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        guard let image = context.makeImage() else { throw SVGImageRenderingError.cannotAllocatePixels }
        return image
    }
}

/// Why an SVG file Graphite did not write has no image.
enum SVGImageRenderingError: Error, LocalizedError, Equatable {
    /// The file is not an SVG document: not XML, or without an `<svg>` element.
    case unreadable
    /// The SVG's width, height or view box gives it no area to draw.
    case noSize
    /// The pixels to draw it into could not be made.
    case cannotAllocatePixels

    var errorDescription: String? {
        switch self {
        case .unreadable: "This SVG file cannot be read."
        case .noSize: "This SVG file has no size."
        case .cannotAllocatePixels: "This SVG file is too large to show."
        }
    }
}
