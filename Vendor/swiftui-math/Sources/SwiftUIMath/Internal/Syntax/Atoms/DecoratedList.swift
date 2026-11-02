/**
 * File: DecoratedList.swift
 * -------------------------
 * Layer: Vendor (SwiftUIMath)
 * Description: Graphite patch: a list with something drawn around, across, above or below
 *              it, or a delimiter of a fixed size, as one atom of its TeX class.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import CoreGraphics
import Foundation

extension Math {
  /// Graphite patch: a list drawn with something around, across, above or below it, or a
  /// delimiter of a fixed size. It stands in its formula as one atom of its `type`, the TeX
  /// class it spaces and breaks as (a relation for `\xrightarrow`, an ordinary atom for
  /// `\boxed`), so the typesetter recognizes it by its class, not by its type.
  final class DecoratedList: Atom {
    enum Decoration {
      /// `\boxed`, `\fbox`: a rectangle around the list.
      case frame
      /// `\textcircled`: a circle around the list.
      case circle
      /// `\cancel` (rising), `\bcancel` (falling), `\xcancel` (both): lines across the list.
      case strikeOut(isRising: Bool, isFalling: Bool)
      /// `\phantom`, `\hphantom`, `\vphantom`: the list's room, without the list.
      case phantom(keepsWidth: Bool, keepsHeight: Bool)
      /// `\mathbin{…}` and its kin: the list as one atom of the class, with nothing added.
      case plainGroup
      /// `\overset`, `\underset`, `\stackrel`: `overList` and `underList` set above and below
      /// the list as an operator's limits.
      case limits
      /// `\xrightarrow`, `\xleftarrow`, `\xleftrightarrow`: an arrow as wide as its labels,
      /// `overList` above it and `underList` below.
      case extensibleArrow(ArrowHeads)
      /// `\overrightarrow`, `\overleftarrow`, `\overleftrightarrow`: an arrow over the list.
      case arrowAbove(ArrowHeads)
      /// `\big(`, `\Bigl[`, …: the delimiter `nucleus`, at least `heightInEm` tall.
      case sizedDelimiter(heightInEm: CGFloat)
      /// `\middle|`: the delimiter `nucleus`, as tall as its `\left…\right` pair.
      case middleDelimiter
    }

    enum ArrowHeads {
      case right
      case left
      case both
    }

    let decoration: Decoration
    var innerList: AtomList?
    var overList: AtomList?
    var underList: AtomList?
    /// `\middle`: the height of its `\left…\right` pair, in points, once the typesetter knows it.
    var stretchedHeight: CGFloat?

    override var finalized: Math.Atom {
      let finalized = super.finalized

      if let decorated = finalized as? DecoratedList {
        decorated.innerList = decorated.innerList?.finalized
        decorated.overList = decorated.overList?.finalized
        decorated.underList = decorated.underList?.finalized
      }

      return finalized
    }

    init(_ decorated: DecoratedList) {
      self.decoration = decorated.decoration
      self.innerList = decorated.innerList.map { AtomList($0) }
      self.overList = decorated.overList.map { AtomList($0) }
      self.underList = decorated.underList.map { AtomList($0) }
      self.stretchedHeight = decorated.stretchedHeight
      super.init(decorated)
    }

    init(decoration: Decoration, type: AtomType = .ordinary, innerList: AtomList? = nil) {
      self.decoration = decoration
      self.innerList = innerList
      super.init(type: type)
    }

    /// The class `\overset` and `\underset` take from what they stand over: a relation
    /// over a relation, a binary operator over one, and ordinary otherwise, as KaTeX does.
    static func limitsClass(of base: AtomList?) -> AtomType {
      guard let atoms = base?.atoms, atoms.count == 1 else { return .ordinary }
      switch atoms[0].type {
      case .relation: return .relation
      case .binaryOperator: return .binaryOperator
      default: return .ordinary
      }
    }
  }
}
