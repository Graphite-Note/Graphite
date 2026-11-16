import SwiftUI
@_spi(Textual) private import SwiftUIMath

struct MathAttachment: Attachment {
  enum DisplayStyle: Sendable {
    case inline
    case block
  }

  /// The formula's source as copied: the whole formula from its first piece, nothing from
  /// the others, so a selection over all of them copies it once.
  var description: String {
    guard pieceIndex == 0 else { return "" }
    switch displayStyle {
    case .inline:
      return "$\(formula)$"
    case .block:
      return "$$\(formula)$$"
    }
  }

  var selectionStyle: AttachmentSelectionStyle {
    .text
  }

  /// What this attachment draws: the formula, or one piece of it.
  let latex: String
  let displayStyle: DisplayStyle
  /// Graphite patch: the whole formula this attachment draws, or draws a piece of.
  let formula: String
  /// Graphite patch: which piece of its formula this is, 0 for a formula drawn whole. Two
  /// equal pieces side by side are still two attachments.
  let pieceIndex: Int

  init(latex: String, style: DisplayStyle) {
    self.init(latex: latex, style: style, formula: latex, pieceIndex: 0)
  }

  private init(latex: String, style: DisplayStyle, formula: String, pieceIndex: Int) {
    self.latex = latex
    self.displayStyle = style
    self.formula = formula
    self.pieceIndex = pieceIndex
  }

  /// Graphite patch: inline math in pieces, a line may break between them
  /// (`InlineMathLineBreaks`); nil when the formula has no place to break, or a piece cannot be
  /// typeset.
  static func inlinePieces(of latex: String) -> [MathAttachment]? {
    guard let pieces = InlineMathLineBreaks.pieces(of: latex), pieces.allSatisfy(canTypeset) else {
      return nil
    }
    return pieces.enumerated().map { pieceIndex, piece in
      MathAttachment(latex: piece, style: .inline, formula: latex, pieceIndex: pieceIndex)
    }
  }

  /// Graphite patch: whether this piece continues the formula of the attachment before it.
  var continuesFormula: Bool { pieceIndex > 0 }

  /// Graphite patch: whether the typesetter can parse `latex`; it measures zero otherwise.
  static func canTypeset(_ latex: String) -> Bool {
    Math.typographicBounds(for: latex, fitting: .unspecified, font: .init(name: .latinModern, size: 12), style: .display).width > 0
  }

  var body: some View {
    MathView(latex: latex, style: displayStyle)
  }

  func baselineOffset(in environment: TextEnvironmentValues) -> CGFloat {
    -typographicBounds(in: environment).descent
  }

  func sizeThatFits(_ proposal: ProposedViewSize, in environment: TextEnvironmentValues) -> CGSize {
    // Graphite patch: math keeps its natural width. Fitting it to a narrow proposal (as
    // table cells make while measuring) broke `$k_n$` onto two lines. Display math is
    // fitted to the proposal only when it is wider than it by more than the tolerance
    // `MathView` draws with, so the reserved size is the size that is drawn.
    let naturalBounds = typographicBounds(in: environment)
    guard displayStyle == .block,
      let width = proposal.width,
      naturalBounds.width > width + Self.naturalWidthTolerance
    else { return naturalBounds.size }
    // Graphite patch: a wide formula on paper keeps its one line, scaled to the column
    // (`MathProperties.WideDisplayMath.scaledToFit`); `MathView` draws it scaled to this size.
    if environment.mathProperties.wideDisplayMath == .scaledToFit, width > 0 {
      return CGSize(width: width, height: naturalBounds.size.height * width / naturalBounds.width)
    }
    return typographicBounds(fitting: proposal, in: environment).size
  }

  /// Graphite patch: how far, in points, display math may overhang its column and still
  /// be measured and drawn on one line at its natural width. Rounded frames are a
  /// fraction of a point narrower than the formula they were measured for.
  static let naturalWidthTolerance: CGFloat = 1

  private func typographicBounds(
    fitting proposal: ProposedViewSize = .unspecified,
    in environment: TextEnvironmentValues
  ) -> Math.TypographicBounds {
    Math.typographicBounds(
      for: latex,
      fitting: proposal,
      font: .init(
        name: .init(environment.mathProperties.fontName),
        size: FontScaled(environment.mathProperties.fontScale).resolve(in: environment)
      ),
      style: .init(displayStyle)
    )
  }
}

private struct MathView: View {
  @Environment(\.textEnvironment) private var environment

  let latex: String
  let style: MathAttachment.DisplayStyle

  private var font: Math.Font {
    .init(
      name: .init(environment.mathProperties.fontName),
      size: FontScaled(environment.mathProperties.fontScale).resolve(in: environment)
    )
  }

  /// Graphite patch: the formula's width on one line, which a formula scaled to its column
  /// is scaled from.
  private var naturalWidth: CGFloat {
    Math.typographicBounds(for: latex, fitting: .unspecified, font: font, style: .init(style)).width
  }

  var body: some View {
    let math = Math(latex)
      .mathFont(font)
      .mathTypesettingStyle(.init(style))
      // Explicit LaTeX colors take precedence; ordinary formulas keep the surrounding style.
      .mathRenderingMode(latex.contains("\\color") || latex.contains("\\textcolor") ? .multicolor : .monochrome)
    // Graphite patch: math is drawn at its natural size. A frame a fraction of a point
    // narrower than the formula (the attachment's measured width, rounded) made it
    // line-break mid-formula, e.g. `E = mc^2` with the exponent on a second line.
    // Display math still wraps when it is genuinely wider than the text column.
    switch style {
    case .inline:
      math.fixedSize(horizontal: true, vertical: false)
    case .block where environment.mathProperties.wideDisplayMath == .scaledToFit:
      ScaledDownToItsFrame(naturalWidth: naturalWidth) { math }
    case .block:
      NaturalWidthWhenItFits { math }
    }
  }
}

/// Graphite patch: draws its subview at its natural size, scaled down uniformly to the
/// width of its frame when it is wider, from its top leading corner. The attachment's frame
/// was measured that way (`MathAttachment.sizeThatFits`), so the formula fills it exactly;
/// a transform keeps the formula's outlines as vectors.
private struct ScaledDownToItsFrame<Content: View>: View {
  let naturalWidth: CGFloat
  @ViewBuilder let content: () -> Content

  var body: some View {
    GeometryReader { geometry in
      let fits = naturalWidth <= geometry.size.width + MathAttachment.naturalWidthTolerance
      content()
        .fixedSize()
        .scaleEffect(fits || naturalWidth <= 0 ? 1 : geometry.size.width / naturalWidth, anchor: .topLeading)
    }
  }
}

/// Graphite patch: proposes a subview its natural width when that fits the space it is
/// given (within `MathAttachment.naturalWidthTolerance`), and the given size otherwise.
struct NaturalWidthWhenItFits: Layout {
  private static let tolerance = MathAttachment.naturalWidthTolerance

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    guard let subview = subviews.first else { return .zero }
    let naturalSize = subview.sizeThatFits(.unspecified)
    if let width = proposal.width, naturalSize.width > width + Self.tolerance {
      return subview.sizeThatFits(proposal)
    }
    return naturalSize
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    guard let subview = subviews.first else { return }
    let naturalSize = subview.sizeThatFits(.unspecified)
    let fits = naturalSize.width <= bounds.width + Self.tolerance
    subview.place(at: bounds.origin, proposal: fits ? .unspecified : ProposedViewSize(bounds.size))
  }
}

extension Math.Font.Name {
  fileprivate init(_ fontName: MathProperties.FontName) {
    self.init(rawValue: fontName.rawValue)
  }
}

extension Math.TypesettingStyle {
  fileprivate init(_ style: MathAttachment.DisplayStyle) {
    switch style {
    case .inline:
      self = .text
    case .block:
      self = .display
    }
  }
}
