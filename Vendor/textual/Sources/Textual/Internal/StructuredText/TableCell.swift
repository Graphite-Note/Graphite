import SwiftUI

extension StructuredText {
  struct TableCell: View {
    @Environment(\.tableCellStyle) private var tableCellStyle

    // Graphite patch: the width the column leaves for the cell's content, which its images
    // fit. Only a cell with such attachments follows it.
    @State private var contentWidth: CGFloat?

    private let content: AttributedSubstring
    private let identifier: TableCell.Identifier
    private let alignment: HorizontalAlignment
    private let fitsAttachmentsToColumn: Bool

    init(
      _ content: AttributedSubstring,
      row: Int,
      column: Int,
      alignment: HorizontalAlignment,
      fitsAttachmentsToColumn: Bool
    ) {
      self.content = content
      self.identifier = .init(row: row, column: column)
      self.alignment = alignment
      self.fitsAttachmentsToColumn = fitsAttachmentsToColumn
    }

    var body: some View {
      let configuration = TableCellStyleConfiguration(
        label: .init(label),
        indentationLevel: indentationLevel,
        row: identifier.row,
        column: identifier.column
      )
      let resolvedStyle =
        tableCellStyle
        .resolve(configuration: configuration)
        .anchorPreference(key: BoundsKey.self, value: .bounds) { anchor in
          [identifier: anchor]
        }

      AnyView(resolvedStyle)
    }

    // Graphite patch: the content fills its column, where `Grid` aligned a cell of the
    // content's own width; the column's width is then the width attachments fit.
    @ViewBuilder
    private var label: some View {
      let text = WithInlineStyle(AttributedString(content)) {
        TextFragment($0)
      }
      .environment(\.attachmentContainerWidth, fitsAttachmentsToColumn ? contentWidth : nil)

      if fitsAttachmentsToColumn {
        // The width its images fit is the width the column offers, never the width of the
        // images themselves: a flexible frame takes the width of content wider than offered,
        // so an image a point wider than its column made the column's width that of the
        // image, which fitted the image to it, and the two took turns for good (HUNT-360).
        ColumnWidthFrame(alignment: alignment) { text }
          .onGeometryChange(for: CGFloat.self) { geometry in
            // Whole points: text as wide as an attachment is rounded up to whole pixels,
            // which would make it wider than a column that ends between two of them.
            geometry.size.width.rounded(.down)
          } action: { newWidth in
            contentWidth = newWidth
          }
      } else {
        text.frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
      }
    }

    private var indentationLevel: Int {
      content.presentationIntent?.indentationLevel ?? 0
    }
  }

  /// Graphite patch: as wide as it is offered, whatever its content's width, with the content
  /// aligned in it; as wide as its content when offered no width.
  struct ColumnWidthFrame: Layout {
    let alignment: HorizontalAlignment

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
      let contentSize = subviews.first?.sizeThatFits(proposal) ?? .zero
      let width = proposal.width.flatMap { width in width.isFinite ? width : nil } ?? contentSize.width
      return CGSize(width: width, height: contentSize.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
      guard let content = subviews.first else { return }
      let contentProposal = ProposedViewSize(width: bounds.width, height: proposal.height)
      let contentWidth = content.sizeThatFits(contentProposal).width
      let spareWidth = bounds.width - contentWidth
      let contentMinX: CGFloat
      switch alignment {
      case .center: contentMinX = bounds.minX + spareWidth / 2
      case .trailing: contentMinX = bounds.minX + spareWidth
      default: contentMinX = bounds.minX
      }
      content.place(at: CGPoint(x: contentMinX, y: bounds.midY), anchor: .leading, proposal: contentProposal)
    }
  }
}

extension StructuredText.TableCell {
  struct Identifier: Hashable {
    let row: Int
    let column: Int
  }

  struct BoundsKey: PreferenceKey {
    static let defaultValue: [Identifier: Anchor<CGRect>] = [:]

    static func reduce(
      value: inout [Identifier: Anchor<CGRect>],
      nextValue: () -> [Identifier: Anchor<CGRect>]
    ) {
      value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
  }
}

extension StructuredText.TableCell {
  struct Spacing: Sendable, Hashable {
    let horizontal: CGFloat?
    let vertical: CGFloat?

    init(horizontal: CGFloat? = nil, vertical: CGFloat? = nil) {
      self.horizontal = horizontal
      self.vertical = vertical
    }
  }

  struct SpacingKey: PreferenceKey {
    static let defaultValue = Spacing()

    static func reduce(value: inout Spacing, nextValue: () -> Spacing) {
      value = nextValue()
    }
  }
}
