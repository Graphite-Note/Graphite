/**
 * File: PencilToolbarStyle.swift
 * ------------------------------
 * Layer: UI
 * Description: Where the Pencil tools show while drawing: the system's palette or Graphite's fixed bar.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

import SwiftUI
import GraphiteCore

/// Where the Pencil tools are shown while drawing.
enum PencilToolbarStyle: String, CaseIterable, Identifiable {
    /// The system's palette, which floats over the page and can be moved or minimized.
    case floating
    /// A bar fixed above the page, as in Goodnotes or Notability.
    case fixed

    var id: String { rawValue }
    var title: String {
        switch self {
        case .floating: "Floating Palette"
        case .fixed: "Fixed Bar"
        }
    }

    static let preferenceKey = "GraphitePencilToolbarStyle"

    /// The style that shows. The system's palette hangs from the window, not from a side: with
    /// two sides shown it floats over both and over the sidebar's edge, and it follows the
    /// focus, so the side not focused has none. A split therefore uses the fixed bar, which
    /// belongs to its side's tab bar, whatever the Settings choice is.
    /// - Parameter sharesWindowWithOtherSide: Whether the window shows two sides at once.
    func inEffect(sharesWindowWithOtherSide: Bool) -> PencilToolbarStyle {
        sharesWindowWithOtherSide ? .fixed : self
    }

    /// The style shown at a width. A phone's compact width always uses the system's palette, which docks at the
    /// bottom of its screen. An iPad keeps the style in effect in a compact window, beside another app: the fixed bar
    /// takes its narrow forms there, and its colors scroll sideways in their strip (requested 2026-11-16); before, the
    /// window showed Apple's palette, whose colors are not the bar's.
    /// - Parameters:
    ///   - horizontalSizeClass: The width class of the view showing the tools.
    ///   - isPhone: Whether the device is a phone (`PencilToolbarStyle.isPhone`).
    func shown(horizontalSizeClass: UserInterfaceSizeClass?, isPhone: Bool) -> PencilToolbarStyle {
        horizontalSizeClass == .compact && isPhone ? .floating : self
    }

    /// Whether this device is a phone, whose compact width always uses the system's palette.
    @MainActor static var isPhone: Bool {
        #if canImport(UIKit)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }
}
