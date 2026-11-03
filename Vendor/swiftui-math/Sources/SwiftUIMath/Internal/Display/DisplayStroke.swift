/**
 * File: DisplayStroke.swift
 * -------------------------
 * Layer: Vendor (SwiftUIMath)
 * Description: Graphite patch: lines drawn as a stroked path, such as a frame's or an
 *              arrow's shaft.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import CoreGraphics
import Foundation

extension Math {
  /// Graphite patch: lines drawn as a path stroked `thickness` wide with butt ends, such as
  /// the frame of `\boxed`, the stroke of `\cancel` or the shaft of an extensible arrow. The
  /// path is in the node's coordinates (y up, origin at its baseline on the left); the node
  /// is as wide, tall and deep as the ink.
  final class DisplayStroke: DisplayNode {
    let path: CGPath
    let thickness: CGFloat

    init(path: CGPath, thickness: CGFloat, range: NSRange) {
      self.path = path
      self.thickness = thickness
      super.init()
      let inkBounds = path.boundingBoxOfPath.insetBy(dx: -thickness / 2, dy: -thickness / 2)
      self.width = max(0, inkBounds.maxX)
      self.ascent = max(0, inkBounds.maxY)
      self.descent = max(0, -inkBounds.minY)
      self.range = range
    }

    /// The area the stroke covers, to be filled.
    var outline: CGPath {
      path.copy(strokingWithWidth: thickness, lineCap: .butt, lineJoin: .miter, miterLimit: 10)
    }
  }
}
