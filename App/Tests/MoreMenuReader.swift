/**
 * File: MoreMenuReader.swift
 * --------------------------
 * Layer: Tests
 * Description: Reads the entries of the More menu of a hosted window's bar, with the submenus that hold them,
 *              as opening the menu fills it: the system's overflow menu on iOS 27, the bar's own More button on 26.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 27/11/2026
 */

#if os(iOS)
import UIKit
import ObjectiveC

/// The More menu of a hosted window's bar. Tests run an entry's action as a tap on it runs it: on iOS 26, UIKit's menu
/// takes no synthesized touch or accessibility activation of its rows.
@MainActor
final class MoreMenuReader {
    /// The More menu's entries: on the iPad its items are the system's overflow menu (•••) of the note's bar, which
    /// the navigation item holds as a deferred element filled when the menu opens, as it is filled here. iOS 26 has no
    /// such menu, and More is a menu button of the bar's own (`MoreToolbarMenu`), whose menu is read instead.
    func entries(in controller: UIViewController) -> [(path: [String], action: UIAction)] {
        let items = navigationItems(in: controller.view)
        if #available(iOS 27, *) {
            return items.compactMap(\.additionalOverflowItems).flatMap { overflow in actions(in: [overflow]) }
        }
        let barButtons = items.flatMap { item in
            item.trailingItemGroups.flatMap(\.barButtonItems) + (item.rightBarButtonItems ?? []) + item.centerItemGroups.flatMap(\.barButtonItems)
        }
        return barButtons.filter { button in button.title == "More" || button.accessibilityLabel == "More" }
            .compactMap(\.menu).flatMap { menu in actions(in: menu.children) }
    }

    private func navigationItems(in view: UIView) -> [UINavigationItem] {
        ((view as? UINavigationBar)?.items ?? []) + view.subviews.flatMap(navigationItems)
    }

    /// The actions among `elements` at any depth, with the titles of the submenus that hold them; a deferred element
    /// is filled as opening its menu fills it.
    private func actions(in elements: [UIMenuElement], path: [String] = []) -> [(path: [String], action: UIAction)] {
        elements.flatMap { element -> [(path: [String], action: UIAction)] in
            if let submenu = element as? UIMenu { return actions(in: submenu.children, path: path + [submenu.title]) }
            if let action = element as? UIAction { return [(path, action)] }
            if let deferred = element as? UIDeferredMenuElement { return actions(in: fulfilledElements(of: deferred), path: path) }
            return []
        }
    }

    /// The elements a deferred element's provider gave, by element, filled as the menu opening asks for them.
    private var providedElements: [ObjectIdentifier: [UIMenuElement]] = [:]

    /// What a deferred element holds: its provider is asked once, as opening the menu asks it, and answers on the
    /// main thread, at once or a moment later; empty until it has answered. UIKit keeps the provider in the
    /// element's `_elementProvider`, a private object whose `__providerBlock` takes the completion.
    private func fulfilledElements(of deferred: UIDeferredMenuElement) -> [UIMenuElement] {
        let key = ObjectIdentifier(deferred)
        if let elements = providedElements[key] { return elements }
        providedElements[key] = []
        guard let providerVariable = class_getInstanceVariable(UIDeferredMenuElement.self, "_elementProvider"),
              let provider = object_getIvar(deferred, providerVariable) as? NSObject,
              let blockVariable = class_getInstanceVariable(type(of: provider), "__providerBlock"),
              let block = object_getIvar(provider, blockVariable) else { return [] }
        typealias Completion = @convention(block) ([UIMenuElement]) -> Void
        typealias Provider = @convention(block) (Completion) -> Void
        let provide = unsafeBitCast(block as AnyObject, to: Provider.self)
        provide { [weak self] elements in self?.providedElements[key] = elements }
        return providedElements[key] ?? []
    }
}
#endif
