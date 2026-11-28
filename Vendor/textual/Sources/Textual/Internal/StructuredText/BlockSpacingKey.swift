import SwiftUI

extension StructuredText {
  struct BlockSpacingKey: PreferenceKey, LayoutValueKey {
    static let defaultValue = BlockSpacing()

    static func reduce(value: inout BlockSpacing, nextValue: () -> BlockSpacing) {
      value = value.union(nextValue())
    }
  }
}

// Graphite patch: the spacing a block asks for reaches the block stack around it in the update
// that makes the block, as a container value, so the stack lays its blocks out at their final
// places in its first pass. The preference reaches the stack only after that pass.
extension ContainerValues {
  /// The spacing a block asks for with `textual.blockSpacing`; nil when it asks for none.
  @Entry var textualRequestedBlockSpacing: StructuredText.BlockSpacing? = nil
  /// The spacing the blocks inside a block ask for, which is the block's own when it asks for
  /// none: a block quote or a list item holds its blocks inside its style's views, out of the
  /// stack's sight, as a stack holds its own.
  @Entry var textualContainedBlockSpacing = StructuredText.BlockSpacing()
}

extension StructuredText {
  /// The spacing the block preference gives a block: the spacing it asks for itself, or else
  /// the union of the spacing its blocks ask for.
  static func blockSpacing(of block: Subview) -> BlockSpacing {
    block.containerValues.textualRequestedBlockSpacing ?? block.containerValues.textualContainedBlockSpacing
  }

  /// The union of the blocks' spacing, which the block preference gives the view around them.
  static func blockSpacing(of blocks: SubviewsCollection) -> BlockSpacing {
    blocks.reduce(BlockSpacing()) { spacing, block in spacing.union(blockSpacing(of: block)) }
  }
}
