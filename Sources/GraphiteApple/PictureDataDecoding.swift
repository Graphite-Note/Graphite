/**
 * File: PictureDataDecoding.swift
 * -------------------------------
 * Layer: Apple
 * Description: Pixels from a picture's bytes read off the web, an SVG included, which ImageIO cannot read: for icons of
 *              notes written as web addresses, such as Notion's own icon set.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 28/11/2026
 */

import Foundation
import CoreGraphics
import ImageIO

/// A picture whose bytes no decoder reads.
public enum PictureDataDecodingError: Error, Equatable {
    case unreadable
}

/// Decodes a picture held in memory, no larger than `maximumPixelDimension` on its longest side.
public enum PictureDataDecoding {
    /// The first bytes looked at to tell an SVG from a raster picture.
    static let sniffedByteCount = 1_024

    public static func image(from pictureData: Data, maximumPixelDimension: Int) throws -> CGImage {
        let limit = PreviewPixelLimit(maximumPixelDimension: maximumPixelDimension)
        if isSVG(pictureData) { return try SVGImageRenderer.image(fromFileData: pictureData, limit: limit) }
        guard let source = CGImageSourceCreateWithData(pictureData as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: limit.maximumPixelDimension,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
              ] as CFDictionary) else { throw PictureDataDecodingError.unreadable }
        return image
    }

    /// Whether the bytes are SVG markup: an `<svg` element near their start, after any XML declaration or comment.
    static func isSVG(_ pictureData: Data) -> Bool {
        let start = String(decoding: pictureData.prefix(sniffedByteCount), as: UTF8.self).lowercased()
        return start.contains("<svg")
    }
}
