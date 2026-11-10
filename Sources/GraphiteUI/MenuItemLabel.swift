/**
 * File: MenuItemLabel.swift
 * -------------------------
 * Layer: UI
 * Description: The label of an entry inside a toolbar's menu, whose symbol the Mac is given as an image
 *              made once per drawing rather than by name.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 10/11/2026
 */

import SwiftUI
#if os(macOS)
import AppKit
#endif

/// An entry's title and SF Symbol inside a toolbar's menu, as `Label(_:systemImage:)` draws it.
///
/// On the Mac the symbol is handed over as an image made when the label is drawn. Given a name,
/// SwiftUI looks the symbol up in the system's asset catalog again each time AppKit asks a
/// toolbar item for its contents, about 20 times when a note's toolbar comes back, and for every
/// entry of its menus: in the owner's Library → List switch half of the toolbar's 1 s went to those
/// lookups (sampled 2026-11-10). With made images five toolbar menus of 18 entries appear in
/// about 55 ms instead of 155 ms more than plain buttons (`MenuItemLabelTests`).
struct MenuItemLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        #if os(macOS)
        Label {
            Text(title)
        } icon: {
            if let symbol = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil) {
                Image(nsImage: symbol)
            } else {
                Image(systemName: systemImage)
            }
        }
        #else
        Label(title, systemImage: systemImage)
        #endif
    }
}

extension Button where Label == MenuItemLabel {
    /// An entry of a toolbar's menu: `Button(_:systemImage:role:action:)` with the symbol made as
    /// an image on the Mac (`MenuItemLabel`).
    init(_ title: String, menuSymbol systemImage: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.init(role: role, action: action) { MenuItemLabel(title: title, systemImage: systemImage) }
    }
}

extension Menu where Label == MenuItemLabel {
    /// A submenu inside a toolbar's menu: `Menu(_:systemImage:content:)` with the symbol made as an
    /// image on the Mac (`MenuItemLabel`).
    init(_ title: String, menuSymbol systemImage: String, @ViewBuilder content: () -> Content) {
        self.init(content: content) { MenuItemLabel(title: title, systemImage: systemImage) }
    }
}
