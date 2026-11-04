/**
 * File: PDFSessionPencilTools.swift
 * ---------------------------------
 * Layer: UI
 * Description: When a PDF shows Graphite's fixed Pencil bar, in a row of its own under the tab bar, or the system's
 *              floating palette.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 04/11/2026
 */

import SwiftUI
import GraphiteCore

#if canImport(UIKit)
import UIKit

extension PDFSession {
    /// Whether the fixed bar's tools are shown for this PDF: the fixed bar is in effect and
    /// shown, the width is not compact, and the PDF can be changed. Read or written on: the
    /// bar is a row above the page, and a row that came with writing pushed the page down
    /// under the Pencil that touched it to write, and laid every page out again at that
    /// first touch (HUNT-312). A tap on the bar while reading starts writing. Not whether
    /// its side is focused: a split opens with the focus on the new side, and the PDF beside
    /// it keeps its tools (they are not one of the window's toolbar items, which follow the
    /// focus).
    func showsFixedPencilTools(style: PencilToolbarStyle, showsTools: Bool, horizontalSizeClass: UserInterfaceSizeClass?) -> Bool {
        style == .fixed && horizontalSizeClass != .compact && showsTools && !isProtected
    }

    /// Whether the system's floating palette is over the page: it has Undo and Redo of its
    /// own, so the document's would repeat them. A compact width always uses the palette, and
    /// arranging a picture puts it away.
    func showsFloatingPencilPalette(style: PencilToolbarStyle, showsTools: Bool, horizontalSizeClass: UserInterfaceSizeClass?, isFocused: Bool) -> Bool {
        (style == .floating || horizontalSizeClass == .compact) && showsTools && isFocused && isWriting && !isProtected && selectedPicture == nil
            && textBoxActivity == .idle
    }
}
#endif
