/**
 * File: PencilWidthText.swift
 * ---------------------------
 * Layer: UI
 * Description: Pencil widths as people speak of a pen on paper, in millimeters.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

import SwiftUI

/// Widths as people speak of a pen on paper: millimeters, a point being 1/72 inch on the
/// page or the drawing.
enum PencilWidthText {
    static let millimetersPerPoint = 25.4 / 72

    static func millimeters(_ widthInPoints: Double) -> String {
        (widthInPoints * millimetersPerPoint).formatted(.number.precision(.fractionLength(1))) + " mm"
    }
}
