/**
 * File: Typesetter+DecoratedList.swift
 * ------------------------------------
 * Layer: Vendor (SwiftUIMath)
 * Description: Graphite patch: the displays of decorated lists, a table's rules, and the
 *              bold forms of symbols.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import CoreGraphics
import CoreText
import Foundation

// MARK: - Bold symbols

/// Graphite patch: the bold form of a symbol the parser gives no alphabet of its own, as it does
/// `\alpha` or `x`: `\boldsymbol{\nabla}` and `\mathbf{\phi}`. `\nabla` is upright, as in
/// MathJax, and other symbols keep the slant of their style. Nil for a style that is not bold
/// or a symbol with no bold form, such as `\times`.
func boldOrdinarySymbol(_ symbol: String, fontStyle: Math.Atom.FontStyle) -> String? {
  guard fontStyle == .bold || fontStyle == .boldItalic, symbol.unicodeScalars.count == 1 else { return nil }
  let isBoldItalic = fontStyle == .boldItalic
  let scalar: UInt32?
  switch symbol.unicodeScalars.first?.value {
  case 0x2207: scalar = 0x1D6C1  // nabla
  case 0x1D715: scalar = isBoldItalic ? 0x1D74F : 0x1D6DB  // partial
  case 0x1D716: scalar = isBoldItalic ? 0x1D750 : 0x1D6DC  // epsilon
  case 0x1D717: scalar = isBoldItalic ? 0x1D751 : 0x1D6DD  // vartheta
  case 0x1D719: scalar = isBoldItalic ? 0x1D753 : 0x1D6DF  // phi
  case 0x1D71A: scalar = isBoldItalic ? 0x1D754 : 0x1D6E0  // varrho
  case 0x1D71B: scalar = isBoldItalic ? 0x1D755 : 0x1D6E1  // varpi
  default: scalar = nil
  }
  return scalar.flatMap(UnicodeScalar.init).map { String(Character($0)) }
}

// MARK: - Decorated lists

/// Graphite patch: the displays of `DecoratedList`, with KaTeX's measures. Lengths are in em
/// of the current style's font: a frame stands 0.3 em from what it holds and its lines are
/// 0.04 em thick (`\fboxsep` and `\fboxrule`), the rule thickness Latin Modern's fraction
/// bars have too.
extension Math.Typesetter {
  private static let ruleThicknessInEm: CGFloat = 0.04
  private static let framePaddingInEm: CGFloat = 0.3
  /// How far a circle stands from what it holds, and the smallest circle, about a capital's size.
  private static let circlePaddingInEm: CGFloat = 0.1
  private static let minimumCircleRadiusInEm: CGFloat = 0.55
  /// The room a struck-out list keeps on each side, and how far the strokes pass its box.
  private static let strikeOutPaddingInEm: CGFloat = 0.1
  /// How far an arrow reaches past its widest label on each side.
  private static let arrowLabelPaddingInEm: CGFloat = 0.3
  /// The narrowest extensible arrow, as KaTeX draws `\xrightarrow{}`.
  private static let minimumArrowWidthInEm: CGFloat = 1.47
  /// The gap between an extensible arrow and its labels, and between a list and the arrow over it.
  private static let arrowGapInEm: CGFloat = 0.1
  /// How far a table's outer rules stand from its rows.
  private static let outerRuleGapInEm: CGFloat = 0.15
  /// How far apart the rules of a double rule are, TeX's `\doublerulesep`.
  private static let doubleRuleGapInEm: CGFloat = 0.2
  /// How far a delimiter may fall short of a size: the font's variants come just under KaTeX's
  /// round heights (2.396 em for 2.4 em), and the next is a whole size larger.
  private static let sizedDelimiterShortfall: CGFloat = 0.98
  /// The width of `\big.`, TeX's `\nulldelimiterspace`.
  private static let nullDelimiterWidthInEm: CGFloat = 0.12

  func makeDecoratedList(_ decorated: Math.DecoratedList) -> Math.DisplayNode {
    let em = styleFont.font.size
    let range = decorated.indexRange
    switch decorated.decoration {
    case .frame:
      // amsmath's `\boxed` sets its content in display style; `\fbox` holds text.
      let inner = line(for: decorated.innerList, style: .display, cramped: false, range: range)
      return framed(inner, padding: Self.framePaddingInEm * em, thickness: Self.ruleThicknessInEm * em, range: range)
    case .circle:
      let inner = line(for: decorated.innerList, style: style, cramped: cramped, range: range)
      return circled(inner, padding: Self.circlePaddingInEm * em, thickness: Self.ruleThicknessInEm * em, range: range)
    case .strikeOut(let isRising, let isFalling):
      // As MathJax's: the list keeps a little room, and the strokes reach past its box.
      let inner = line(for: decorated.innerList, style: style, cramped: cramped, range: range)
      let padding = Self.strikeOutPaddingInEm * em
      inner.position = CGPoint(x: padding, y: 0)
      let width = inner.width + 2 * padding
      let strokes = CGMutablePath()
      if isRising {
        strokes.move(to: CGPoint(x: 0, y: -inner.descent - padding))
        strokes.addLine(to: CGPoint(x: width, y: inner.ascent + padding))
      }
      if isFalling {
        strokes.move(to: CGPoint(x: 0, y: inner.ascent + padding))
        strokes.addLine(to: CGPoint(x: width, y: -inner.descent - padding))
      }
      let stroke = Math.DisplayStroke(path: strokes, thickness: Self.ruleThicknessInEm * em, range: range)
      let display = Math.DisplayList(children: [inner, stroke], range: range)
      display.width = width
      return display
    case .phantom(let keepsWidth, let keepsHeight):
      let inner = line(for: decorated.innerList, style: style, cramped: cramped, range: range)
      let room = Math.DisplayNode()
      room.width = keepsWidth ? inner.width : 0
      room.ascent = keepsHeight ? inner.ascent : 0
      room.descent = keepsHeight ? inner.descent : 0
      room.range = range
      return room
    case .plainGroup:
      return line(for: decorated.innerList, style: style, cramped: cramped, range: range)
    case .limits:
      let base = line(for: decorated.innerList, style: style, cramped: cramped, range: range)
      return withLimits(base, over: labelAbove(decorated, range: range), under: labelBelow(decorated, range: range), gap: nil, range: range)
    case .extensibleArrow(let heads):
      let over = labelAbove(decorated, range: range)
      let under = labelBelow(decorated, range: range)
      let labelWidth = max(over?.width ?? 0, under?.width ?? 0)
      let arrow = horizontalArrow(
        width: max(labelWidth + 2 * Self.arrowLabelPaddingInEm * em, Self.minimumArrowWidthInEm * em), heads: heads, range: range)
      return withLimits(arrow, over: over, under: under, gap: Self.arrowGapInEm * em, range: range)
    case .arrowAbove(let heads):
      let inner = line(for: decorated.innerList, style: style, cramped: true, range: range)
      let arrow = horizontalArrow(width: inner.width, heads: heads, range: range)
      let width = max(inner.width, arrow.width)
      inner.position = CGPoint(x: (width - inner.width) / 2, y: 0)
      arrow.position = CGPoint(x: (width - arrow.width) / 2, y: inner.ascent + Self.arrowGapInEm * em + arrow.descent)
      return Math.DisplayList(children: [inner, arrow], range: range)
    case .middleDelimiter:
      guard !decorated.nucleus.isEmpty,
        let delimiter = findGlyphForBoundary(decorated.nucleus, withHeight: decorated.stretchedHeight ?? 0)
      else {
        let room = Math.DisplayNode()
        room.range = range
        return room
      }
      delimiter.range = range
      return Math.DisplayList(children: [delimiter], range: range)
    case .sizedDelimiter(let heightInEm):
      guard !decorated.nucleus.isEmpty,
        let delimiter = findGlyphForBoundary(decorated.nucleus, withHeight: heightInEm * em * Self.sizedDelimiterShortfall)
      else {
        let room = Math.DisplayNode()
        room.width = Self.nullDelimiterWidthInEm * em
        room.range = range
        return room
      }
      delimiter.range = range
      return Math.DisplayList(children: [delimiter], range: range)
    }
  }

  /// The rules of a table whose rows are positioned, in the table's coordinates: `\hline`
  /// between rows, or just outside the first or last, as wide as the columns and any rules
  /// outside them, and an array's `|` halfway between columns, as tall as the rows. A rule
  /// before the first column moves the rows right to make room for it; one after the last
  /// stands the same distance out.
  func makeTableRules(_ table: Math.Table, rows: [Math.DisplayNode], columnWidths: [CGFloat]) -> [Math.DisplayNode] {
    guard !table.horizontalRuleRows.isEmpty || !table.verticalRuleColumns.isEmpty,
      let firstRow = rows.first, let lastRow = rows.last
    else { return [] }
    let em = styleFont.font.size
    let thickness = Self.ruleThicknessInEm * em
    let columnSpacing = max(table.interColumnSpacing * styleFont.metrics.mathUnit, Self.outerRuleGapInEm * em)
    let leftInset = table.verticalRuleColumns.contains(0) ? columnSpacing / 2 : 0
    if leftInset > 0 {
      for row in rows { row.position.x += leftInset }
    }
    let spacing = table.interColumnSpacing * styleFont.metrics.mathUnit
    let contentWidth = columnWidths.reduce(0, +) + spacing * CGFloat(max(0, columnWidths.count - 1))
    let hasRightRule = table.verticalRuleColumns.contains(columnWidths.count)
    let rightEnd = leftInset + contentWidth + (hasRightRule ? columnSpacing / 2 : 0)
    var rules: [Math.DisplayNode] = []

    let top = firstRow.position.y + firstRow.ascent + Self.outerRuleGapInEm * em
    let bottom = lastRow.position.y - lastRow.descent - Self.outerRuleGapInEm * em
    var previousRow: Int?
    var repeatCount = 0
    for rowIndex in table.horizontalRuleRows.sorted() where rowIndex <= rows.count {
      repeatCount = rowIndex == previousRow ? repeatCount + 1 : 0
      previousRow = rowIndex
      let height: CGFloat
      if rowIndex == 0 {
        height = top
      } else if rowIndex == rows.count {
        height = bottom
      } else {
        height = (rows[rowIndex - 1].position.y - rows[rowIndex - 1].descent + rows[rowIndex].position.y + rows[rowIndex].ascent) / 2
      }
      let rule = CGMutablePath()
      let ruleHeight = height - CGFloat(repeatCount) * Self.doubleRuleGapInEm * em
      rule.move(to: CGPoint(x: 0, y: ruleHeight))
      rule.addLine(to: CGPoint(x: rightEnd, y: ruleHeight))
      rules.append(Math.DisplayStroke(path: rule, thickness: thickness, range: table.indexRange))
    }

    var previousColumn: Int?
    repeatCount = 0
    for column in table.verticalRuleColumns.sorted() where column <= columnWidths.count {
      repeatCount = column == previousColumn ? repeatCount + 1 : 0
      previousColumn = column
      let columnStart = columnWidths.prefix(column).reduce(0, +) + spacing * CGFloat(column)
      let ruleX = leftInset + columnStart - columnSpacing / 2 + CGFloat(repeatCount) * Self.doubleRuleGapInEm * em
      let rule = CGMutablePath()
      rule.move(to: CGPoint(x: ruleX, y: top))
      rule.addLine(to: CGPoint(x: ruleX, y: bottom))
      rules.append(Math.DisplayStroke(path: rule, thickness: thickness, range: table.indexRange))
    }
    return rules
  }

  /// A list typeset on one line, or an empty one.
  private func line(for list: Math.AtomList?, style: Math.Style.Level, cramped: Bool, range: NSRange) -> Math.DisplayList {
    Math.Typesetter.createLineForMathList(list, font: font, style: style, cramped: cramped)
      ?? Math.DisplayList(children: [], range: range)
  }

  private func labelAbove(_ decorated: Math.DecoratedList, range: NSRange) -> Math.DisplayList? {
    decorated.overList.map { list in line(for: list, style: scriptStyle(), cramped: superScriptCramped(), range: range) }
  }

  private func labelBelow(_ decorated: Math.DecoratedList, range: NSRange) -> Math.DisplayList? {
    decorated.underList.map { list in line(for: list, style: scriptStyle(), cramped: subscriptCramped(), range: range) }
  }

  /// `inner` in a rectangle `padding` from its box, the rectangle's lines `thickness` wide.
  private func framed(_ inner: Math.DisplayList, padding: CGFloat, thickness: CGFloat, range: NSRange) -> Math.DisplayList {
    let outset = padding + thickness / 2
    let rectangle = CGPath(
      rect: CGRect(x: thickness / 2, y: -(inner.descent + outset), width: inner.width + 2 * outset, height: inner.ascent + inner.descent + 2 * outset),
      transform: nil)
    inner.position = CGPoint(x: padding + thickness, y: 0)
    return Math.DisplayList(children: [inner, Math.DisplayStroke(path: rectangle, thickness: thickness, range: range)], range: range)
  }

  /// `inner` centred in a circle wide and tall enough for its box, `padding` beyond it.
  private func circled(_ inner: Math.DisplayList, padding: CGFloat, thickness: CGFloat, range: NSRange) -> Math.DisplayList {
    let height = inner.ascent + inner.descent
    let radius = max(max(inner.width, height) / 2 + padding, Self.minimumCircleRadiusInEm * styleFont.font.size)
    let center = CGPoint(x: thickness / 2 + radius, y: (inner.ascent - inner.descent) / 2)
    let circle = CGPath(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius), transform: nil)
    inner.position = CGPoint(x: center.x - inner.width / 2, y: 0)
    return Math.DisplayList(children: [inner, Math.DisplayStroke(path: circle, thickness: thickness, range: range)], range: range)
  }

  /// `base` with `over` and `under` centred above and below it as an operator's limits, at
  /// `gap` from it, or at the font's gaps for limits when `gap` is nil.
  private func withLimits(_ base: Math.DisplayNode, over: Math.DisplayList?, under: Math.DisplayList?, gap: CGFloat?, range: NSRange) -> Math.DisplayNode {
    guard over != nil || under != nil else { return base }
    let display = Math.DisplayLargeOperator(nucleus: base, upperLimit: over, lowerLimit: under, limitShift: 0, extraPadding: 0)
    if let over {
      display.upperLimitGap = gap ?? max(styleFont.metrics.upperLimitGapMin, styleFont.metrics.upperLimitBaselineRiseMin - over.descent)
    }
    if let under {
      display.lowerLimitGap = gap ?? max(styleFont.metrics.lowerLimitGapMin, styleFont.metrics.lowerLimitBaselineDropMin - under.ascent)
    }
    display.range = range
    return display
  }

  /// A horizontal arrow at least `width` wide, its shaft on the math axis. Its heads are the
  /// font's own arrow glyphs (`→` and `←`, their shafts included), joined by a rule as thick
  /// as their shafts that starts where a glyph's shaft ends, so the two never overlap: a
  /// formula's outlines are filled as one path, where overlaps of opposite winding are holes.
  /// The arrow is never narrower than its heads.
  private func horizontalArrow(width: CGFloat, heads: Math.DecoratedList.ArrowHeads, range: NSRange) -> Math.DisplayList {
    let rightHead = heads == .left ? nil : arrowGlyph("\u{2192}", range: range)
    let leftHead = heads == .right ? nil : arrowGlyph("\u{2190}", range: range)
    let arrowWidth = max(width, (rightHead?.inkBounds.width ?? 0) + (leftHead?.inkBounds.width ?? 0))
    var children: [Math.DisplayNode] = []
    var shaftStart: CGFloat = 0
    var shaftEnd = arrowWidth
    var shaft: (center: CGFloat, thickness: CGFloat)?
    if let leftHead {
      // The tip at the left edge; the glyph's shaft ends at its ink's right edge.
      leftHead.display.position = CGPoint(x: -leftHead.inkBounds.minX, y: 0)
      shaftStart = leftHead.inkBounds.width
      shaft = leftHead.shaft
      children.append(leftHead.display)
    }
    if let rightHead {
      rightHead.display.position = CGPoint(x: arrowWidth - rightHead.inkBounds.maxX, y: 0)
      shaftEnd = arrowWidth - rightHead.inkBounds.width
      shaft = shaft ?? rightHead.shaft
      children.append(rightHead.display)
    }
    if let shaft, shaftEnd > shaftStart {
      let rule = CGMutablePath()
      rule.move(to: CGPoint(x: shaftStart, y: shaft.center))
      rule.addLine(to: CGPoint(x: shaftEnd, y: shaft.center))
      children.append(Math.DisplayStroke(path: rule, thickness: shaft.thickness, range: range))
    }
    let arrow = Math.DisplayList(children: children, range: range)
    arrow.width = arrowWidth
    return arrow
  }

  private struct ArrowGlyph {
    let display: Math.DisplayGlyph
    let inkBounds: CGRect
    /// The height of the center of the glyph's shaft above the baseline, and its thickness.
    let shaft: (center: CGFloat, thickness: CGFloat)
  }

  /// The arrow glyph for `character`, with its shaft measured from its outline at its tail,
  /// a twentieth of its ink from the end that has no head.
  private func arrowGlyph(_ character: String, range: NSRange) -> ArrowGlyph? {
    var glyph = findGlyphForCharacterAtIndex(character.startIndex, inString: character)
    guard glyph != 0, let outline = CTFontCreatePathForGlyph(styleFont.ctFont, glyph, nil) else { return nil }
    let inkBounds = CTFontGetBoundingRectsForGlyphs(styleFont.ctFont, .horizontal, &glyph, nil, 1)
    let advance = CTFontGetAdvancesForGlyphs(styleFont.ctFont, .horizontal, &glyph, nil, 1)
    let pointsRight = character == "\u{2192}"
    let tailX = pointsRight ? inkBounds.minX + inkBounds.width / 20 : inkBounds.maxX - inkBounds.width / 20
    var shaft = (center: styleFont.metrics.axisHeight, thickness: Self.ruleThicknessInEm * styleFont.font.size)
    if outline.contains(CGPoint(x: tailX, y: inkBounds.midY)) {
      let top = edge(of: outline, atX: tailX, from: inkBounds.midY, toward: inkBounds.maxY)
      let bottom = edge(of: outline, atX: tailX, from: inkBounds.midY, toward: inkBounds.minY)
      shaft = (center: (top + bottom) / 2, thickness: top - bottom)
    }
    let display = Math.DisplayGlyph(glyph: glyph, font: styleFont.font, range: range)
    var ascent = CGFloat(0)
    var descent = CGFloat(0)
    getBboxDetails(inkBounds, ascent: &ascent, descent: &descent)
    display.ascent = ascent
    display.descent = descent
    display.width = advance
    return ArrowGlyph(display: display, inkBounds: inkBounds, shaft: shaft)
  }

  /// Where the outline's ink ends at `x`, going from `inside` (in the ink) toward `outside`.
  private func edge(of outline: CGPath, atX x: CGFloat, from inside: CGFloat, toward outside: CGFloat) -> CGFloat {
    var inkHeight = inside
    var blankHeight = outside
    for _ in 0..<20 {
      let middle = (inkHeight + blankHeight) / 2
      if outline.contains(CGPoint(x: x, y: middle)) { inkHeight = middle } else { blankHeight = middle }
    }
    return (inkHeight + blankHeight) / 2
  }
}
