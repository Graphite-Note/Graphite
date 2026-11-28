import SwiftUI

extension StructuredText {
  struct Paragraph: View {
    @Environment(\.paragraphStyle) private var paragraphStyle

    private let content: AttributedSubstring

    init(_ content: AttributedSubstring) {
      self.content = content
    }

    var body: some View {
      let configuration = BlockStyleConfiguration(
        label: .init(label),
        indentationLevel: indentationLevel
      )
      let resolvedStyle = paragraphStyle.resolve(configuration: configuration)

      AnyView(resolvedStyle)
    }

    private var label: some View {
      WithInlineStyle(AttributedString(content)) { styled in
        // Graphite patch: a paragraph marked with `TruncatedLinesAttribute` draws each line on one
        // line of its own (patch 38).
        if TruncatedLines.isMarked(styled) {
          TruncatedLines(content: styled)
        } else {
          TextFragment(styled)
        }
      }
    }

    private var indentationLevel: Int {
      content.presentationIntent?.indentationLevel ?? 0
    }
  }
}
