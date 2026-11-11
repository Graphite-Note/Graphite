import SwiftUI

/// Graphite addition: an item of the menu a host gives a link of selectable ``StructuredText``.
public struct TextLinkMenuItem {
  public let title: String
  /// An SF Symbol's name.
  public let systemImage: String
  public let action: @MainActor () -> Void

  public init(title: String, systemImage: String, action: @escaping @MainActor () -> Void) {
    self.title = title
    self.systemImage = systemImage
    self.action = action
  }
}

/// Graphite addition: what a host does with some links of selectable ``StructuredText``
/// beyond following them, such as a picture that carries a link to its zoom.
public struct TextLinkInteractions {
  /// The link's own menu: shown for a long press on a touch screen and for a secondary
  /// click, before the text's own items on the Mac. Empty for a link the text's menu serves.
  public let menuItems: @MainActor (URL) -> [TextLinkMenuItem]
  /// A link tapped or clicked with modifier keys held, such as Command: true when the host
  /// handled it, which then is not followed.
  public let openWithModifiers: @MainActor (URL, EventModifiers) -> Bool

  public init(
    menuItems: @escaping @MainActor (URL) -> [TextLinkMenuItem],
    openWithModifiers: @escaping @MainActor (URL, EventModifiers) -> Bool
  ) {
    self.menuItems = menuItems
    self.openWithModifiers = openWithModifiers
  }
}

extension EnvironmentValues {
  /// Nil unless a host asks: links then have only the text's own menu and are followed
  /// whatever keys are held.
  @Entry var textLinkInteractions: TextLinkInteractions? = nil
}

extension TextualNamespace where Base: View {
  /// Graphite addition: gives the links of selectable text a host's own menu and what a
  /// click with modifier keys does.
  public func linkInteractions(_ interactions: TextLinkInteractions?) -> some View {
    base.environment(\.textLinkInteractions, interactions)
  }
}

#if TEXTUAL_ENABLE_TEXT_SELECTION && canImport(UIKit)
  import UIKit

  extension UIKeyModifierFlags {
    /// The keys held, as SwiftUI names them.
    var eventModifiers: EventModifiers {
      var modifiers: EventModifiers = []
      if contains(.command) { modifiers.insert(.command) }
      if contains(.alternate) { modifiers.insert(.option) }
      if contains(.shift) { modifiers.insert(.shift) }
      if contains(.control) { modifiers.insert(.control) }
      return modifiers
    }
  }
#elseif TEXTUAL_ENABLE_TEXT_SELECTION && canImport(AppKit)
  import AppKit

  extension NSEvent.ModifierFlags {
    /// The keys held, as SwiftUI names them.
    var eventModifiers: EventModifiers {
      var modifiers: EventModifiers = []
      if contains(.command) { modifiers.insert(.command) }
      if contains(.option) { modifiers.insert(.option) }
      if contains(.shift) { modifiers.insert(.shift) }
      if contains(.control) { modifiers.insert(.control) }
      return modifiers
    }
  }
#endif
