import SwiftUI

// MARK: - Overview
//
// `WithInlineStyle` applies an `InlineStyle` to an `AttributedString` before it reaches the
// rendering pipeline.
//
// The input `AttributedString` is expected to carry inline semantics using standard Foundation
// attributes:
// - `inlinePresentationIntent` identifies spans like code, emphasis, strong, and strikethrough.
// - `link` identifies URLs.
//
// The view reads `InlineStyle` and `TextEnvironmentValues` from the environment, then produces a
// styled copy of the attributed string by merging attributes into each matching span.
//
// Styling is recomputed whenever the input, style, or environment snapshot changes, in the
// update that shows it (Graphite patch 31).

struct WithInlineStyle<Content: View>: View {
  @Environment(\.inlineStyle) private var style
  @Environment(\.textEnvironment) private var environment

  // Graphite patch: the styled text is made in the update that first shows the view, kept in a
  // holder no view observes (`StyledText`, made again only when the input, the style or the
  // environment changes). Upstream made it in `onChange`, so every text fragment was first laid
  // out empty and then again with its text, and the view around it twice over.
  @State private var styledText = StyledText()

  private let input: AttributedString
  private let content: (AttributedString) -> Content

  init(
    _ input: AttributedString,
    @ViewBuilder content: @escaping (AttributedString) -> Content
  ) {
    self.input = input
    self.content = content
  }

  var body: some View {
    content(styledText.output(for: Tuple(input, style, environment)))
  }

  /// Graphite patch: the styled text last made, and what it was made from.
  @MainActor final class StyledText {
    private var source: Tuple<AttributedString, InlineStyle, TextEnvironmentValues>?
    private var output = AttributedString()

    func output(for source: Tuple<AttributedString, InlineStyle, TextEnvironmentValues>) -> AttributedString {
      if let madeFrom = self.source, madeFrom == source { return output }
      output = WithInlineStyle.styled(source.values.0, style: source.values.1, in: source.values.2)
      self.source = source
      return output
    }
  }

  fileprivate static func styled(
    _ attributedString: AttributedString,
    style: InlineStyle,
    in environment: TextEnvironmentValues
  ) -> AttributedString {
    var output = attributedString

    for run in attributedString.runs {
      var attributes = AttributeContainer()

      if let intent = run.inlinePresentationIntent {
        if intent.contains(.code) {
          style.code.apply(in: &attributes, environment: environment)
        }

        if intent.contains(.emphasized) {
          style.emphasis.apply(in: &attributes, environment: environment)
        }

        if intent.contains(.stronglyEmphasized) {
          style.strong.apply(in: &attributes, environment: environment)
        }

        if intent.contains(.strikethrough) {
          style.strikethrough.apply(in: &attributes, environment: environment)
        }
      }

      if run.link != nil {
        style.link.apply(in: &attributes, environment: environment)
      }

      output[run.range].mergeAttributes(attributes, mergePolicy: .keepNew)
    }

    return output
  }
}
