import SwiftUI

// MARK: - Overview
//
// TextFragment renders attributed content as SwiftUI.Text with support for inline
// attachments, links, and selection. It uses a TextBuilder to construct and cache
// Text values, minimizing rebuilds during resize by keying on attachment sizes.
//
// Attachments are represented as placeholder images tagged with AttachmentAttribute. The
// actual attachment views are rendered in an overlay using the resolved Text.Layout
// geometry. Three modifiers are applied at the fragment level:
//
// - TextSelectionBackground renders selection highlights on macOS
// - AttachmentOverlay draws attachments at their run locations with selection-aware dimming
// - TextLinkInteraction handles tap gestures on links
//
// These overlays use backgroundPreferenceValue and overlayPreferenceValue to access
// Text.Layout and render in fragment-local coordinates. Fragment-level overlays enable
// coordinate space isolation and keep scrollable regions interactive.
//
// An ancestor view must define a named coordinate space (.textContainer) for the text
// container. TextFragment uses onGeometryChange to observe the container size and rebuild
// Text when attachment sizes need to change.
//
// TextFragment is used by InlineText and StructuredText (via BlockContent) to render
// attributed content with inline attachments, links, and selection.

struct TextFragment<Content: AttributedStringProtocol>: View {
  @Environment(\.textEnvironment) private var textEnvironment
  // Graphite patch: a table cell gives its own width, which its attachments fit instead of
  // the width of the whole text container.
  @Environment(\.attachmentContainerWidth) private var attachmentContainerWidth
  // Graphite patch: the text is built in the update that first shows the fragment, kept in a
  // holder that is not observed (`TextBuilderHolder`); upstream built it in `onChange`, so a
  // fragment was first laid out empty and then again with its text.
  @State private var builderHolder = TextBuilderHolder()

  private let content: Content

  init(_ content: Content) {
    self.content = content
  }

  var body: some View {
    let textBuilder = builderHolder.builder(
      for: content,
      attachmentProposal: attachmentContainerWidth.map { width in
        ProposedViewSize(width: width, height: nil)
      } ?? .unspecified,
      environment: textEnvironment
    )
    let attachments = content.attachments()
    textBuilder.text
      .customAttribute(TextFragmentAttribute())
      .onGeometryChange(for: CGSize?.self, of: \.textContainerSize) { size in
        guard let size, attachmentContainerWidth == nil else { return }
        builderHolder.builder?.sizeChanged(size, environment: textEnvironment)
      }
      .onChange(of: attachmentContainerWidth) { _, newWidth in
        guard let newWidth else { return }
        builderHolder.builder?.proposalChanged(
          ProposedViewSize(width: newWidth, height: nil),
          environment: textEnvironment
        )
      }
      // Graphite patch: each overlay reads the text's layout only where the text has what it
      // draws or takes, so a plain line of text makes none of their geometry readers.
      .modifier(RoundedRunBackgrounds(isNeeded: content.runs.contains { run in run[RoundedRunBackgroundAttribute.self] != nil }))
      .modifier(TextSelectionBackground())
      .modifier(ReadingHighlight())
      .modifier(AttachmentOverlay(attachments: attachments))
      .modifier(TextLinkInteraction(isNeeded: content.runs.contains { run in run.link != nil }))
  }
}

extension TextFragment {
  /// Graphite patch: the fragment's text builder, made again only when the fragment's content
  /// changes. Not observed: making the builder in a view update changes no state any view reads;
  /// the builder itself is observed, so a new size of the attachments draws the text again.
  @MainActor final class TextBuilderHolder {
    private(set) var builder: TextBuilder?
    private var builtContent: Content?

    func builder(
      for content: Content,
      attachmentProposal: ProposedViewSize,
      environment: TextEnvironmentValues
    ) -> TextBuilder {
      if let builder, let builtContent, builtContent == content {
        return builder
      }
      let builder = TextBuilder(content, attachmentProposal: attachmentProposal, environment: environment)
      self.builder = builder
      builtContent = content
      return builder
    }
  }
}

struct TextFragmentAttribute: TextAttribute {
}

extension Text.Layout {
  var isTextFragment: Bool {
    first?.first?[TextFragmentAttribute.self] != nil
  }
}

extension CoordinateSpaceProtocol where Self == NamedCoordinateSpace {
  static var textContainer: NamedCoordinateSpace {
    .named("textContainer")
  }
}

extension GeometryProxy {
  fileprivate var textContainerSize: CGSize? {
    bounds(of: .textContainer)?.size
  }
}

extension EnvironmentValues {
  /// Graphite patch: the width a text fragment's attachments fit, in place of the text
  /// container's width; nil outside a table cell.
  @Entry var attachmentContainerWidth: CGFloat? = nil
}
