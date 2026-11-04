/**
 * File: HangingAttachmentPlacement.swift
 * --------------------------------------
 * Layer: Vendor (Textual)
 * Description: Graphite patch: the placeholder for an attachment that hangs below the baseline,
 *              shaped so its line grows only by what the attachment needs.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 02/11/2026
 */

import CoreText
import SwiftUI

/// The placeholder for an attachment that hangs below the baseline, and where the attachment
/// goes on it.
///
/// SwiftUI measures a line around an image with a negative baseline offset as if the offset
/// moved nothing up and everything down: the line's ascent stays the image's whole height, and
/// its descent is the font's descent plus the offset, even when the font's descent had room for
/// it. An attachment set with its own height and descent paid for its descent twice and for the
/// font's descent once more.
///
/// So the placeholder is only the part above the baseline, moved down only by the part of the
/// descent the font's line does not already hold. The line then has the taller of the two
/// ascents and the taller of the two descents. The placeholder is no longer where the attachment
/// is, so whatever needs the attachment's place asks `frame(onPlaceholderBounds:)`.
struct HangingAttachmentPlacement: Hashable, Sendable {
  /// SwiftUI draws an image of height 0 at a default size of 32 points. A height this small adds
  /// nothing to a line, since a line is always as tall as its font.
  private static let smallestPlaceholderHeight: CGFloat = 1

  private let attachmentSize: CGSize
  private let attachmentAscent: CGFloat

  let placeholderSize: CGSize
  let placeholderBaselineOffset: CGFloat

  /// Nil for an attachment that does not hang below the baseline: its placeholder is set as it is.
  init?(attachmentSize: CGSize, baselineOffset: CGFloat, fontLineDescent: CGFloat) {
    guard baselineOffset < 0 else { return nil }
    let attachmentDescent = -baselineOffset
    self.attachmentSize = attachmentSize
    self.attachmentAscent = attachmentSize.height - attachmentDescent
    self.placeholderSize = CGSize(
      width: attachmentSize.width,
      height: max(attachmentAscent, Self.smallestPlaceholderHeight)
    )
    self.placeholderBaselineOffset = min(fontLineDescent - attachmentDescent, 0)
  }

  /// The attachment's frame, given the bounds SwiftUI laid out for its placeholder.
  func frame(onPlaceholderBounds placeholderBounds: CGRect) -> CGRect {
    let baseline = placeholderBounds.maxY + placeholderBaselineOffset
    return CGRect(
      x: placeholderBounds.minX,
      y: baseline - attachmentAscent,
      width: placeholderBounds.width,
      height: attachmentSize.height
    )
  }
}

extension AnyAttachment {
  /// Whether this sits among words, whose line it should not push apart. Display math is a block
  /// of its own: the room SwiftUI gives it is part of how far it stands from the text around it.
  var isSetInALineOfText: Bool {
    (base as? MathAttachment)?.displayStyle != .block
  }
}

extension TextEnvironmentValues {
  /// The descent a line in this font has, rounded as SwiftUI rounds it. Without the API that tells
  /// (no system Graphite runs on), it is 0, and a line reserves the font's descent on top of the
  /// attachment's as it did before.
  var fontLineDescent: CGFloat {
    guard #available(iOS 26, macOS 26, tvOS 26, watchOS 26, visionOS 26, *) else { return 0 }
    var environment = EnvironmentValues()
    environment.dynamicTypeSize = dynamicTypeSize
    environment.legibilityWeight = legibilityWeight
    return CTFontGetDescent((font ?? .body).resolve(in: environment.fontResolutionContext).ctFont).rounded()
  }
}
