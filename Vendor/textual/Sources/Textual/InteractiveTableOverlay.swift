import SwiftUI

extension StructuredText {
  /// Graphite addition: the links of a table's cells, for an overlay that takes the table's
  /// touches and clicks (``TextualNamespace/interactiveTableOverlay(content:)``) and so keeps
  /// them from the text selection overlay, which follows links everywhere else.
  ///
  /// The cells' text is looked up only when asked, as at a tap, not each time it is laid out.
  public struct TableLinks {
    #if TEXTUAL_ENABLE_TEXT_SELECTION
      private let layouts: (any TextLayoutCollection)?

      init(_ layouts: (any TextLayoutCollection)?) {
        self.layouts = layouts
      }
    #endif

    /// No links, as for a table not laid out yet.
    public static var none: TableLinks { TableLinks() }

    init() {
      #if TEXTUAL_ENABLE_TEXT_SELECTION
        layouts = nil
      #endif
    }

    /// The link drawn under `point`, in the overlay's coordinates; nil off a link.
    @MainActor public func url(at point: CGPoint) -> URL? {
      #if TEXTUAL_ENABLE_TEXT_SELECTION
        layouts?.url(for: point)
      #else
        nil
      #endif
    }
  }
}

/// The table's layout and its links, read from two preferences of the table and met here,
/// since an overlay reads one preference only. Both are resolved in the table's own space.
struct InteractiveTableOverlayKey: PreferenceKey {
  struct Value {
    var layout: StructuredText.TableLayout?
    var links: StructuredText.TableLinks?
  }

  static var defaultValue: Value { Value() }

  static func reduce(value: inout Value, nextValue: () -> Value) {
    let next = nextValue()
    value.layout = next.layout ?? value.layout
    value.links = next.links ?? value.links
  }
}

extension View {
  /// Reports the links of the text laid out in this view, in its own space, for
  /// `InteractiveTableOverlayKey`.
  func reportingTableLinks() -> some View {
    #if TEXTUAL_ENABLE_TEXT_SELECTION
      overlayPreferenceValue(Text.LayoutKey.self) { textLayouts in
        GeometryReader { geometry in
          Color.clear.preference(
            key: InteractiveTableOverlayKey.self,
            value: .init(links: .init(LiveTextLayoutCollection(base: textLayouts, geometry: geometry)))
          )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
      }
    #else
      self
    #endif
  }
}
