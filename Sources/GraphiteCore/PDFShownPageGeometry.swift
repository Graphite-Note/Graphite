/**
 * File: PDFShownPageGeometry.swift
 * --------------------------------
 * Layer: Core
 * Description: A PDF page as a view shows it (its crop box, its quarter turns and where it is drawn, which carries
 *              the zoom), and the point of the page under a point of the view, for pictures dropped onto pages.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

import Foundation
import CoreGraphics

/// A PDF page as a view shows it. The page's own coordinates count up from the bottom of its
/// crop box; the view shows the box turned clockwise by `quarterTurnsClockwise` and drawn
/// in `frameInView`, whose size against the box's is the zoom.
public struct PDFShownPage: Equatable, Sendable {
    /// The crop box in the page's own coordinates.
    public let cropBox: CGRect
    /// How many quarter turns clockwise the page is shown at (its `/Rotate` over 90), from 0 to 3.
    public let quarterTurnsClockwise: Int
    /// Where the page is drawn, turned, in the view's coordinates.
    public let frameInView: CGRect
    /// Whether the view's vertical axis runs down, as UIKit's and a flipped AppKit view's do.
    public let viewIsFlipped: Bool

    public init(cropBox: CGRect, rotationDegrees: Int, frameInView: CGRect, viewIsFlipped: Bool) {
        self.cropBox = cropBox
        quarterTurnsClockwise = ((rotationDegrees / 90) % 4 + 4) % 4
        self.frameInView = frameInView
        self.viewIsFlipped = viewIsFlipped
    }

    /// The point of the page under a point of the view, kept inside the crop box: a drop
    /// beside the page, or in the gap after it, lands at its nearest edge.
    public func pagePoint(ofViewPoint viewPoint: CGPoint) -> CGPoint {
        guard frameInView.width > 0, frameInView.height > 0 else { return CGPoint(x: cropBox.midX, y: cropBox.midY) }
        // How far across and down the page as shown, as fractions of its shown width and height.
        let across = min(max((viewPoint.x - frameInView.minX) / frameInView.width, 0), 1)
        let downward = min(max(viewIsFlipped ? (viewPoint.y - frameInView.minY) / frameInView.height
                                             : (frameInView.maxY - viewPoint.y) / frameInView.height, 0), 1)
        let width = cropBox.width, height = cropBox.height
        // The shown top-left corner is the box's top-left unturned, its bottom-left turned a
        // quarter clockwise, its bottom-right turned a half, and its top-right turned three quarters.
        switch quarterTurnsClockwise {
        case 1: return CGPoint(x: cropBox.minX + downward * width, y: cropBox.minY + across * height)
        case 2: return CGPoint(x: cropBox.maxX - across * width, y: cropBox.minY + downward * height)
        case 3: return CGPoint(x: cropBox.maxX - downward * width, y: cropBox.maxY - across * height)
        default: return CGPoint(x: cropBox.minX + across * width, y: cropBox.maxY - downward * height)
        }
    }

    /// A distance and direction as the page is shown (`rightward` and `downward`, in points of
    /// the page), as the same move in the page's own coordinates: an arrow key moves a picture
    /// the way it points on screen, whatever the page's turn.
    public static func pageVector(rightward: CGFloat, downward: CGFloat, quarterTurnsClockwise: Int) -> CGVector {
        switch ((quarterTurnsClockwise % 4) + 4) % 4 {
        case 1: CGVector(dx: downward, dy: rightward)
        case 2: CGVector(dx: -rightward, dy: downward)
        case 3: CGVector(dx: -downward, dy: -rightward)
        default: CGVector(dx: rightward, dy: -downward)
        }
    }
}
