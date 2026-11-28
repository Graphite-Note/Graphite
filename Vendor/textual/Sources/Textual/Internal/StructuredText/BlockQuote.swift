import SwiftUI

extension StructuredText {
  struct BlockQuote: View {
    @Environment(\.blockQuoteStyle) private var blockQuoteStyle

    private let intent: PresentationIntent.IntentType?
    private let content: AttributedSubstring

    init(intent: PresentationIntent.IntentType?, content: AttributedSubstring) {
      self.intent = intent
      self.content = content
    }

    var body: some View {
      // Graphite patch: the quote's blocks are read as subviews, whose spacing the quote
      // passes on to the block stack around it (patch 36); the style holds them in its views.
      Group(subviews: BlockContent(parent: intent, content: content)) { blocks in
        let configuration = BlockStyleConfiguration(
          label: .init(blocks),
          indentationLevel: indentationLevel
        )
        let resolvedStyle = blockQuoteStyle.resolve(configuration: configuration)

        AnyView(resolvedStyle)
          .containerValue(\.textualContainedBlockSpacing, StructuredText.blockSpacing(of: blocks))
      }
    }

    private var indentationLevel: Int {
      content.runs.first?.presentationIntent?.indentationLevel ?? 0
    }
  }
}
