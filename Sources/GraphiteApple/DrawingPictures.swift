/**
 * File: DrawingPictures.swift
 * ---------------------------
 * Layer: Apple
 * Description: Prepares an image file to be drawn on: the picture is decoded with its orientation
 *              applied, reduced to the sharpness a saved drawing has (twice the canvas width in pixels),
 *              and placed at the full canvas width.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 01/11/2026
 */
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import GraphiteCore

/// Prepares an image file to be drawn on: the picture is decoded with its orientation
/// applied, reduced to the sharpness a saved drawing has (twice the canvas width in
/// pixels), and placed at the full canvas width. The original file is only read.
public enum DrawingPictures {
    /// Pixels kept per point of canvas, the scale of a saved PNG drawing.
    static let pixelsPerPoint = DrawingLimits.preferredPNGScale
    /// JPEG quality for opaque pictures; photos keep their detail at a fraction of PNG's size.
    static let photographQuality = 0.9

    public static func picture(from imageData: Data, canvasWidth: Double) throws -> DrawingBackgroundImage {
        guard canvasWidth.isFinite, canvasWidth > 0,
              let source = CGImageSourceCreateWithData(imageData as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let storedWidth = properties[kCGImagePropertyPixelWidth] as? Int, let storedHeight = properties[kCGImagePropertyPixelHeight] as? Int,
              storedWidth > 0, storedHeight > 0 else {
            throw GraphiteError.invalidFile("Graphite cannot draw on this kind of image.")
        }
        // EXIF orientations 5 to 8 turn the picture a quarter turn.
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        let isTurned = (5...8).contains(orientation)
        let displayedWidth = Double(isTurned ? storedHeight : storedWidth)
        let displayedHeight = Double(isTurned ? storedWidth : storedHeight)
        let frameHeight = canvasWidth * displayedHeight / displayedWidth
        guard frameHeight <= DrawingLimits.maximumCanvasHeight else {
            throw GraphiteError.oversized("This image is too tall to draw on.")
        }
        let longestStoredSide = max(storedWidth, storedHeight)
        let longestKeptSide = min(longestStoredSide, Int((max(canvasWidth, frameHeight) * pixelsPerPoint).rounded(.up)))
        guard let picture = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: longestKeptSide,
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary) else {
            throw GraphiteError.invalidFile("This image could not be read.")
        }
        let encodedPicture = try encode(picture)
        guard encodedPicture.count <= DrawingLimits.maximumBackgroundImageBytes else {
            throw GraphiteError.oversized("This image is too large to draw on.")
        }
        return DrawingBackgroundImage(imageData: encodedPicture, frame: CGRect(x: 0, y: 0, width: canvasWidth, height: frameHeight))
    }

    /// JPEG for opaque pictures, PNG for pictures with transparency.
    private static func encode(_ picture: CGImage) throws -> Data {
        try encode(picture, as: hasTransparency(picture) ? .png : .jpeg)
    }

    private static func hasTransparency(_ picture: CGImage) -> Bool {
        ![CGImageAlphaInfo.none, .noneSkipFirst, .noneSkipLast].contains(picture.alphaInfo)
    }

    private static func encode(_ picture: CGImage, as type: UTType) throws -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else {
            throw GraphiteError.invalidFile("Cannot prepare the image.")
        }
        let options = type == .png ? nil : [kCGImageDestinationLossyCompressionQuality: photographQuality] as CFDictionary
        CGImageDestinationAddImage(destination, picture, options)
        guard CGImageDestinationFinalize(destination) else { throw GraphiteError.invalidFile("Cannot prepare the image.") }
        return output as Data
    }

    // MARK: Pictures on PDF pages

    /// A picture ready to be placed on a PDF page, with the size of its pixels as shown upright.
    public struct PagePicture: Sendable, Equatable {
        public let imageData: Data
        public let pixelSize: CGSize
    }

    /// More pixels than this are more than any page shows; the same bound as a lassoed area's picture.
    static let maximumPagePicturePixelCount = 24_000_000
    /// How far each attempt reduces a picture whose encoded bytes are over the bound.
    private static let reductionPerAttempt = 0.8
    private static let maximumReductionAttempts = 12

    /// Prepares an image for a PDF page, which is zoomed far past the size it is first shown
    /// at and which keeps no other copy to go back to: the picture keeps every pixel it has.
    /// A JPEG or PNG that is upright and within `PDFPicture.maximumImageBytes` stays the very
    /// file it is, so a screenshot's text is not smudged by a JPEG and a photo is not encoded
    /// again. Anything else is decoded once with its orientation applied: a picture with
    /// transparency or a PNG stays a PNG, others become a JPEG at `photographQuality`. Only a
    /// picture over the page's bounds of pixels or bytes is reduced, as little as fits them.
    public static func pagePicture(from imageData: Data) throws -> PagePicture {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let storedWidth = properties[kCGImagePropertyPixelWidth] as? Int, let storedHeight = properties[kCGImagePropertyPixelHeight] as? Int,
              storedWidth > 0, storedHeight > 0 else {
            throw GraphiteError.invalidFile("Graphite cannot place this kind of image on a page.")
        }
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        let isUpright = orientation == 1
        let pixelCount = Double(storedWidth) * Double(storedHeight)
        let sourceType = CGImageSourceGetType(source).flatMap { identifier in UTType(identifier as String) }
        if isUpright, sourceType == .jpeg || sourceType == .png, imageData.count <= PDFPicture.maximumImageBytes,
           pixelCount <= Double(maximumPagePicturePixelCount) {
            return PagePicture(imageData: imageData, pixelSize: CGSize(width: storedWidth, height: storedHeight))
        }
        let pixelReduction = min(1, (Double(maximumPagePicturePixelCount) / pixelCount).squareRoot())
        var longestSide = Double(max(storedWidth, storedHeight)) * pixelReduction
        for _ in 0..<maximumReductionAttempts {
            guard let picture = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: Int(longestSide.rounded()),
                kCGImageSourceShouldCacheImmediately: true,
            ] as CFDictionary) else {
                throw GraphiteError.invalidFile("This image could not be read.")
            }
            // An opaque PNG too large as a PNG goes on as a JPEG before it loses any pixels.
            let types: [UTType] = hasTransparency(picture) ? [.png] : sourceType == .png ? [.png, .jpeg] : [.jpeg]
            for type in types {
                let encodedPicture = try encode(picture, as: type)
                if encodedPicture.count <= PDFPicture.maximumImageBytes {
                    return PagePicture(imageData: encodedPicture, pixelSize: CGSize(width: picture.width, height: picture.height))
                }
            }
            longestSide *= reductionPerAttempt
        }
        throw GraphiteError.oversized("This image is too large to place on a page.")
    }
}
