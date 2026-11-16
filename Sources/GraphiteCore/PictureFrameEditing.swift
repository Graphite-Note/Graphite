/**
 * File: PictureFrameEditing.swift
 * -------------------------------
 * Layer: Core
 * Description: Moving and resizing a picture's frame by a corner, also when the picture is turned by any angle: the
 *              corner opposite the one dragged stays where it is and the picture keeps its proportions.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

import Foundation
import CoreGraphics

/// A corner of a picture's frame, the upright rectangle it fills before it is turned, named
/// by the frame's own edges in the coordinates it is given in.
public enum PictureFrameCorner: CaseIterable, Sendable {
    case minimumXMinimumY, maximumXMinimumY, minimumXMaximumY, maximumXMaximumY

    public var opposite: PictureFrameCorner {
        switch self {
        case .minimumXMinimumY: .maximumXMaximumY
        case .maximumXMinimumY: .minimumXMaximumY
        case .minimumXMaximumY: .maximumXMinimumY
        case .maximumXMaximumY: .minimumXMinimumY
        }
    }

    /// Whether the corner is on the frame's larger x and larger y edges.
    var isOnMaximumX: Bool { self == .maximumXMinimumY || self == .maximumXMaximumY }
    var isOnMaximumY: Bool { self == .minimumXMaximumY || self == .maximumXMaximumY }

    /// The corner of `frame` before it is turned.
    public func point(of frame: CGRect) -> CGPoint {
        CGPoint(x: isOnMaximumX ? frame.maxX : frame.minX, y: isOnMaximumY ? frame.maxY : frame.minY)
    }

    /// Where the corner is once `frame` is turned by `radians` about its middle (`PictureRotation`).
    public func point(of frame: CGRect, turnedBy radians: Double) -> CGPoint {
        PictureRotation.point(point(of: frame), turnedBy: radians, about: CGPoint(x: frame.midX, y: frame.midY))
    }
}

/// Moving and resizing a picture's frame. Angles turn the x axis toward the y axis of the
/// coordinates used, as in `PictureRotation`.
public enum PictureFrameEditing {
    /// The frame resized by dragging `corner` to `point`, both where they are with the frame
    /// turned by `radians`: the opposite corner stays put, the proportions are kept, and no side
    /// gets narrower than `narrowestSide`. The result is the frame before it is turned.
    public static func resized(_ frame: CGRect, turnedBy radians: Double, draggingCorner corner: PictureFrameCorner,
                               to point: CGPoint, narrowestSide: CGFloat) -> CGRect {
        guard frame.width > 0, frame.height > 0 else { return frame }
        let anchor = corner.opposite.point(of: frame, turnedBy: radians)
        // The drag along the picture's own edges, from the corner that stays.
        let along = PictureRotation.vector(CGPoint(x: point.x - anchor.x, y: point.y - anchor.y), turnedBy: -radians)
        let horizontalSign: CGFloat = corner.isOnMaximumX ? 1 : -1, verticalSign: CGFloat = corner.isOnMaximumY ? 1 : -1
        let scale = max(horizontalSign * along.x / frame.width, verticalSign * along.y / frame.height,
                        narrowestSide / min(frame.width, frame.height))
        let width = frame.width * scale, height = frame.height * scale
        let middleOffset = PictureRotation.vector(CGPoint(x: horizontalSign * width / 2, y: verticalSign * height / 2), turnedBy: radians)
        return CGRect(x: anchor.x + middleOffset.x - width / 2, y: anchor.y + middleOffset.y - height / 2, width: width, height: height)
    }

    /// The frame moved by a distance and direction.
    public static func moved(_ frame: CGRect, by offset: CGVector) -> CGRect {
        frame.offsetBy(dx: offset.dx, dy: offset.dy)
    }
}
