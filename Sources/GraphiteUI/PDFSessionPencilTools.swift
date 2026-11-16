/**
 * File: PDFSessionPencilTools.swift
 * ---------------------------------
 * Layer: UI
 * Description: When a PDF shows Graphite's fixed Pencil bar, in a row of its own under the tab bar, or the system's
 *              floating palette.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 16/11/2026
 */

import SwiftUI
import GraphiteCore

#if canImport(UIKit)
import UIKit

extension PDFSession {
    /// Whether the fixed bar's tools are shown for this PDF: the fixed bar is in effect and
    /// shown at this width (a phone's compact width uses the palette, an iPad's keeps the bar:
    /// `PencilToolbarStyle.shown`), and the PDF can be changed. Read or written on: the
    /// bar is a row above the page, and a row that came with writing pushed the page down
    /// under the Pencil that touched it to write, and laid every page out again at that
    /// first touch (HUNT-312). A tap on the bar while reading starts writing. Not whether
    /// its side is focused: a split opens with the focus on the new side, and the PDF beside
    /// it keeps its tools (they are not one of the window's toolbar items, which follow the
    /// focus).
    func showsFixedPencilTools(style: PencilToolbarStyle, showsTools: Bool, horizontalSizeClass: UserInterfaceSizeClass?) -> Bool {
        style.shown(horizontalSizeClass: horizontalSizeClass, isPhone: PencilToolbarStyle.isPhone) == .fixed && showsTools && !isProtected
    }

    /// Whether the system's floating palette is over the page: it has Undo and Redo of its
    /// own, so the document's would repeat them. A phone's compact width always uses the
    /// palette, and arranging a picture puts it away.
    func showsFloatingPencilPalette(style: PencilToolbarStyle, showsTools: Bool, horizontalSizeClass: UserInterfaceSizeClass?, isFocused: Bool) -> Bool {
        style.shown(horizontalSizeClass: horizontalSizeClass, isPhone: PencilToolbarStyle.isPhone) == .floating && showsTools && isFocused && isWriting && !isProtected && selectedPicture == nil
            && textBoxActivity == .idle
    }
}
#endif
