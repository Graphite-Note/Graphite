import SwiftUI

// MARK: - Overview
//
// OrderedList aligns all list item markers to a consistent width for uniform layout. Each marker
// measures itself and reports its width via preferences. The maximum width is taken and applied
// to all markers, ensuring alignment even when marker widths vary (e.g., "1." vs "10.").

extension StructuredText {
  struct OrderedList: View {
    @Environment(\.listItemSpacing) private var listItemSpacing
    @Environment(\.textEnvironment) private var textEnvironment

    @State private var markerWidth: CGFloat?

    private let intent: PresentationIntent.IntentType?
    private let content: AttributedSubstring

    init(intent: PresentationIntent.IntentType?, content: AttributedSubstring) {
      self.intent = intent
      self.content = content
    }

    var body: some View {
      let runs = content.blockRuns(parent: intent)
      // Graphite patch: every marker is laid out as wide as the list's largest ordinal's, which
      // for decimal markers (monospaced digits) is the widest, so the markers line up in the
      // first pass. Upstream lined them up only in a second pass, with the widest width the
      // first pass reported; that is still done when the markers came out of different widths.
      let sizingOrdinal = runs.compactMap { run -> Int? in
        guard case .listItem(let ordinal) = run.intent?.kind else { return nil }
        return ordinal
      }.max() ?? 0

      BlockVStack {
        ForEach(runs.indices, id: \.self) { index in
          let run = runs[index]

          OrderedListItem(
            intent: run.intent,
            content: content[run.range],
            sizingOrdinal: sizingOrdinal,
            markerWidth: markerWidth
          )
        }
      }
      .onPreferenceChange(MarkerWidthKey.self) { @MainActor widths in
        guard let widths else { return }
        // Markers already of one width need no frame; once given one, they keep following the widest.
        guard widths.narrowest != widths.widest || markerWidth != nil else { return }
        if markerWidth != widths.widest { markerWidth = widths.widest }
      }
      .environment(\.resolvedListItemSpacing, listItemSpacing.resolve(in: textEnvironment))
      .environment(\.listItemSpacingEnabled, true)
    }
  }
}

extension StructuredText {
  fileprivate struct OrderedListItem: View {
    @Environment(\.listItemStyle) private var listItemStyle
    @Environment(\.orderedListMarker) private var orderedListMarker

    private let intent: PresentationIntent.IntentType?
    private let content: AttributedSubstring
    private let sizingOrdinal: Int
    private let markerWidth: CGFloat?

    init(
      intent: PresentationIntent.IntentType?,
      content: AttributedSubstring,
      sizingOrdinal: Int,
      markerWidth: CGFloat?
    ) {
      self.intent = intent
      self.content = content
      self.sizingOrdinal = sizingOrdinal
      self.markerWidth = markerWidth
    }

    var body: some View {
      let configuration = ListItemStyleConfiguration(
        marker: .init(marker),
        block: .init(
          BlockContent(
            parent: intent,
            content: content
          )
        ),
        indentationLevel: indentationLevel,
        content: content
      )
      let resolvedStyle = listItemStyle.resolve(configuration: configuration)

      AnyView(resolvedStyle)
    }

    private var marker: some View {
      ZStack(alignment: .trailing) {
        if sizingOrdinal != ordinal {
          resolvedMarker(ordinal: sizingOrdinal)
            .hidden()
            .accessibilityHidden(true)
        }
        resolvedMarker(ordinal: ordinal)
      }
      .background {
        // Propagate the marker width
        GeometryReader { proxy in
          Color.clear
            .preference(
              key: MarkerWidthKey.self,
              value: MarkerWidths(narrowest: proxy.size.width, widest: proxy.size.width)
            )
        }
      }
      .frame(width: markerWidth, alignment: .trailing)
    }

    private func resolvedMarker(ordinal: Int) -> AnyView {
      AnyView(
        orderedListMarker.resolve(
          configuration: .init(
            indentationLevel: indentationLevel,
            ordinal: ordinal
          )
        )
      )
    }

    private var indentationLevel: Int {
      content.runs.first?.presentationIntent?.indentationLevel ?? 0
    }

    private var ordinal: Int {
      guard case .listItem(let ordinal) = intent?.kind else {
        return 0
      }
      return ordinal
    }
  }

  /// The narrowest and the widest width the list's markers were laid out at.
  fileprivate struct MarkerWidths: Equatable {
    var narrowest: CGFloat
    var widest: CGFloat
  }

  fileprivate struct MarkerWidthKey: PreferenceKey {
    static let defaultValue: MarkerWidths? = nil

    static func reduce(value: inout MarkerWidths?, nextValue: () -> MarkerWidths?) {
      guard let next = nextValue() else { return }
      guard let current = value else {
        value = next
        return
      }
      value = MarkerWidths(narrowest: min(current.narrowest, next.narrowest), widest: max(current.widest, next.widest))
    }
  }
}
