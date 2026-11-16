/**
 * File: PictureNaturalSize.swift
 * ------------------------------
 * Layer: Apple
 * Description: The size an image is shown at by its own measure: its pixels upright, and its width in points at the
 *              resolution it states, or at half its pixels as on a Retina screen.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

import Foundation
import CoreGraphics
import ImageIO

/// The size an image is shown at by its own measure, read from its header only.
public enum PictureNaturalSize {
    /// A picture's pixels as shown upright, and the width in points it is placed at before
    /// it is kept to the room there is.
    public struct Measure: Equatable, Sendable {
        public let shownPixelSize: CGSize
        public let widthInPoints: CGFloat
    }

    /// Points per inch on paper, which a stated resolution is measured against.
    private static let pointsPerInch = 72.0
    /// Pixels per point of a picture that states no resolution, as on a Retina screen.
    private static let pixelsPerPointWithoutResolution = 2.0
    /// EXIF orientations 5 to 8 turn the picture a quarter turn.
    private static let quarterTurnedOrientations = 5...8

    /// The measure of an image ImageIO reads: an image with a stated resolution at that size
    /// on paper, any other at half its pixels. Nil when the image cannot be read.
    public static func measure(ofImageData imageData: Data) -> Measure? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let pixelWidth = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let pixelHeight = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue, pixelWidth > 0 else { return nil }
        let isTurned = quarterTurnedOrientations.contains((properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1)
        let shownPixelSize = CGSize(width: isTurned ? pixelHeight : pixelWidth, height: isTurned ? pixelWidth : pixelHeight)
        if let dotsPerInch = (properties[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue, dotsPerInch > pointsPerInch {
            return Measure(shownPixelSize: shownPixelSize, widthInPoints: CGFloat(Double(shownPixelSize.width) * pointsPerInch / dotsPerInch))
        }
        return Measure(shownPixelSize: shownPixelSize, widthInPoints: CGFloat(Double(shownPixelSize.width) / pixelsPerPointWithoutResolution))
    }
}
