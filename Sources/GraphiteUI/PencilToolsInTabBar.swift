/**
 * File: PencilToolsInTabBar.swift
 * -------------------------------
 * Layer: UI
 * Description: The fixed bar's Pencil tools at the end of a side's tab bar, and when a PDF shows the fixed tools or
 *              the system's palette.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import SwiftUI
import GraphiteCore

#if canImport(UIKit)
import UIKit

/// The fixed bar's tools at the end of a side's tab bar, for the PDF its active tab shows,
/// while that PDF is written on: in the row that is there anyway rather than a row of their
/// own above the page. The side decides whether its tab bar has room.
struct TabBarPencilTools: View {
    let session: PDFSession
    /// Whether the Read Aloud core plugin is on, which the Read Aloud pen belongs to.
    let offersReadAloudPen: Bool
    @AppStorage(PencilToolbarStyle.preferenceKey) private var chosenToolbarStyle = PencilToolbarStyle.floating
    @Environment(\.sharesWindowWithOtherSide) private var sharesWindowWithOtherSide
    @AppStorage(PDFAnnotationPreferenceKey.showsToolPicker) private var showsToolPicker = true
    @AppStorage(PDFAnnotationPreferenceKey.drawsShapes) private var drawsShapes = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var pictureSource: PDFPictureSource?

    var body: some View {
        if session.showsFixedPencilTools(style: chosenToolbarStyle.inEffect(sharesWindowWithOtherSide: sharesWindowWithOtherSide),
                                         showsTools: showsToolPicker, horizontalSizeClass: horizontalSizeClass) {
            PencilToolRow(toolbox: PencilToolbox.shared, drawsShapes: $drawsShapes,
                          addImage: { pictureSource = .photoLibrary }, undoAvailability: session.undoAvailability, rowHeight: PencilToolbarMetrics.heightInTabBar,
                          offersReadAloudPen: offersReadAloudPen, offersTextBoxes: true)
                .modifier(PDFPictureAdding(session: session, source: $pictureSource))
        }
    }
}

extension PDFSession {
    /// Whether the fixed bar's tools are shown for this PDF: the fixed bar is in effect and
    /// shown, the width is not compact, and the PDF is written on and can be changed. Not
    /// whether its side is focused: a split opens with the focus on the new side, and the
    /// PDF beside it, still written on, keeps its tools (they are not one of the window's
    /// toolbar items, which follow the focus).
    func showsFixedPencilTools(style: PencilToolbarStyle, showsTools: Bool, horizontalSizeClass: UserInterfaceSizeClass?) -> Bool {
        style == .fixed && horizontalSizeClass != .compact && showsTools && isWriting && !isProtected
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
