import SwiftUI

// MARK: - Overview
//
// BlockVStack arranges blocks vertically with CSS-style margin collapsing behavior. Adjacent
// blocks' top and bottom spacing collapses by taking the maximum value rather than summing,
// matching how CSS margins work.
//
// List items can override block spacing with environment-driven list item spacing for consistent
// spacing within lists regardless of individual block preferences.

extension StructuredText {
  struct BlockVStack<Content: View>: View {
    @Environment(\.multilineTextAlignment) private var textAlignment

    private let content: Content

    init(@ViewBuilder content: () -> Content) {
      self.content = content()
    }

    var body: some View {
      Group(subviews: content) { children in
        BlockVStackLayout(textAlignment: textAlignment) {
          ForEach(children) { child in
            BlockLayoutView(child, requestedBlockSpacing: StructuredText.blockSpacing(of: child))
          }
        }
        // Graphite patch: the stack's spacing, as the block preference gives it, for a stack
        // around this one (patch 36).
        .containerValue(\.textualContainedBlockSpacing, StructuredText.blockSpacing(of: children))
      }
    }
  }
}

extension StructuredText {
  struct BlockAlignmentKey: LayoutValueKey {
    static let defaultValue: TextAlignment? = nil
  }

  fileprivate struct BlockLayoutView<Content: View>: View {
    @Environment(\.listItemSpacingEnabled) private var listItemSpacingEnabled
    @Environment(\.resolvedListItemSpacing) private var resolvedListItemSpacing

    /// The spacing the preference gave, kept only when it is not the requested one.
    @State private var preferredBlockSpacing: BlockSpacing?

    private let content: Content
    private let requestedBlockSpacing: BlockSpacing

    init(_ content: Content, requestedBlockSpacing: BlockSpacing) {
      self.content = content
      self.requestedBlockSpacing = requestedBlockSpacing
    }

    var body: some View {
      // Graphite patch: a list's items are spaced by the list item spacing alone, which the
      // environment already holds; read from the preference, as upstream did, it reached the
      // layout only in a second pass, after the first had spaced the items by their views.
      if listItemSpacingEnabled {
        content
          .layoutValue(key: BlockSpacingKey.self, value: resolvedListItemSpacing)
      } else {
        // Graphite patch: the block is spaced at once by the spacing it requests, which its
        // container values hold in the update that makes it (patch 36). Upstream spaced it by
        // the preference alone, which reached the layout only in a second pass, after the
        // first had spaced the blocks by their views. The preference is still read: a style
        // that requests its spacing inside a view of its own, out of the container values'
        // reach, is spaced by it in a second pass, as upstream.
        let blockSpacing = preferredBlockSpacing ?? requestedBlockSpacing
        content
          .onPreferenceChange(BlockSpacingKey.self) { @MainActor value in
            if value != blockSpacing { preferredBlockSpacing = value }
          }
          .layoutValue(key: BlockSpacingKey.self, value: blockSpacing)
      }
    }
  }

  fileprivate struct BlockVStackLayout: Layout {
    struct Cache {
      let spacings: [CGFloat]
    }

    let textAlignment: TextAlignment

    func makeCache(subviews: Subviews) -> Cache {
      return Cache(
        spacings: subviews.indices.dropLast().map { index in
          let current = subviews[index]
          let next = subviews[index + 1]
          let currentBottom = current[BlockSpacingKey.self].bottom
          let nextTop = next[BlockSpacingKey.self].top

          // Take the maximum block spacing, otherwise the preferred view spacing
          return [currentBottom, nextTop].compactMap(\.self).max()
            ?? current.spacing.distance(to: next.spacing, along: .vertical)
        }
      )
    }

    func sizeThatFits(
      proposal: ProposedViewSize,
      subviews: Subviews, cache: inout Cache
    ) -> CGSize {
      if let width = proposal.width, width <= 0 {
        return .zero
      }

      var size = CGSize.zero

      for view in subviews {
        let viewSize = view.sizeThatFits(.init(width: proposal.width, height: nil))
        size.height += viewSize.height
        size.width = max(size.width, viewSize.width)
      }

      size.height += cache.spacings.reduce(0, +)

      return size
    }

    func placeSubviews(
      in bounds: CGRect,
      proposal: ProposedViewSize,
      subviews: Subviews, cache: inout Cache
    ) {
      var currentY: CGFloat = 0

      for (index, view) in zip(subviews.indices, subviews) {
        let viewProposal = ProposedViewSize(width: proposal.width, height: nil)
        let viewSize = view.sizeThatFits(viewProposal)

        var point = bounds.origin
        let alignment = view[BlockAlignmentKey.self] ?? textAlignment

        switch alignment {
        case .leading:
          break  // do nothing
        case .center:
          point.x += (bounds.width - viewSize.width) / 2
        case .trailing:
          point.x += bounds.width - viewSize.width
        }

        point.y += currentY

        view.place(at: point, proposal: viewProposal)

        currentY += viewSize.height

        if index < subviews.count - 1 {
          currentY += cache.spacings[index]
        }
      }
    }
  }
}

@available(tvOS, unavailable)
@available(watchOS, unavailable)
#Preview {
  @Previewable @State var textAlignment = TextAlignment.leading
  @Previewable @State var blockSpacing: CGFloat = 1

  VStack {
    GroupBox {
      Picker("Text Alignment", selection: $textAlignment) {
        Text("Leading").tag(TextAlignment.leading)
        Text("Center").tag(TextAlignment.center)
        Text("Trailing").tag(TextAlignment.trailing)
      }
      .pickerStyle(.segmented)
      HStack {
        Text("2nd / 3rd Spacing")
        Slider(value: $blockSpacing, in: 0...3)
      }
    }
    Spacer()
    StructuredText.BlockVStack {
      Text(
        """
        Listen to your sister, Morty. To live is to risk it all, otherwise you’re just an inert \
        chunk of randomly assembled molecules drifting wherever the universe blows you.
        """
      )
      .textual.blockSpacing(.fontScaled(bottom: 1))
      Text(
        """
        Listen, Morty, I hate to break it to you but what people call "love" is just a chemical \
        reaction that compels animals to breed. It hits hard, Morty, then it slowly fades, \
        leaving you stranded in a failing marriage. I did it. Your parents are gonna do it. \
        Break the cycle, Morty. Rise above. Focus on science.
        """
      )
      .textual.blockSpacing(.fontScaled(bottom: blockSpacing))
      Text(
        """
        Wow, I really Cronenberged up the whole place, huh Morty? Just a bunch a Cronenbergs \
        walkin' around.
        """
      )
      .textual.blockSpacing(.fontScaled(top: 1, bottom: 1))
    }
    .border(Color.red)
    Spacer()
  }
  .multilineTextAlignment(textAlignment)
  .padding()
}
