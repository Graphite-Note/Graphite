/**
 * File: PencilPaletteCompanionButtons.swift
 * -----------------------------------------
 * Layer: UI
 * Description: Graphite's own Pencil actions as buttons of a PDF's toolbar while Apple's floating palette is on screen:
 *              Add Image, the text tool, Graphite's lasso, the laser pointer and the Read Aloud pen, one tap away as on
 *              the Fixed Bar (HUNT-309).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 04/11/2026
 */

import SwiftUI

#if canImport(UIKit)
import UIKit

/// The actions the Fixed Bar has and Apple's floating palette cannot hold, as toolbar buttons beside the PDF's own while
/// the palette is on screen: Add Image (a tap opens the photo library, a long press offers a file or the pasteboard's
/// picture), the text tool, Graphite's lasso (Select Ink), the laser pointer, and the Read Aloud pen where it is on.
/// They take up the room of the Undo and Redo buttons, which the palette has of its own, so the toolbar keeps its row
/// and nothing is added to the screen; what the toolbar has no room for is in its overflow menu, as for its other
/// buttons. The tools are the window's (`PaletteInkSelection`), the same the palette's Graphite button turns on.
struct PencilPaletteCompanionButtons: View {
    let session: PDFSession
    @Binding var pictureSource: PDFPictureSource?
    var offersReadAloudPen = false
    /// The window's Graphite tools, which the palette's canvases follow.
    let inkSelection: () -> PaletteInkSelection
    /// The tool in use, read again whenever it changes, in the palette's menu or here.
    @State private var toolInUse = PaletteInkSelection.Tool.none

    var body: some View {
        Group {
            Menu {
                PDFAddImageMenuContent(session: session, source: $pictureSource)
            } label: {
                Label("Add Image", systemImage: "photo.badge.plus")
            } primaryAction: {
                pictureSource = .photoLibrary
            }
            toolButton("Text Box", tool: .textBox, image: Image(systemName: PencilToolKind.text.symbolName))
            toolButton("Select Ink", tool: .lasso, image: Image(systemName: LassoShape.stored.symbolName))
            toolButton("Laser Pointer", tool: .laser, image: glyph(LaserPointerGlyph.templateImage(), else: PencilToolKind.laser.symbolName))
            if offersReadAloudPen {
                toolButton("Read Aloud Pen", tool: .readAloudPen, image: glyph(ReadAloudPenGlyph.templateImage(), else: PencilToolKind.readAloud.symbolName))
            }
        }
        .onAppear { toolInUse = inkSelection().tool }
        .onReceive(NotificationCenter.default.publisher(for: PaletteInkSelection.didChange)) { _ in toolInUse = inkSelection().tool }
    }

    /// A tool's own glyph, as the bar and the palette draw it, or its symbol.
    private func glyph(_ templateImage: UIImage?, else symbolName: String) -> Image {
        templateImage.map { image in Image(uiImage: image) } ?? Image(systemName: symbolName)
    }

    /// One of Graphite's tools: a tap takes it up, a tap on the tool in use puts it away and gives the palette's tool back.
    private func toolButton(_ title: String, tool: PaletteInkSelection.Tool, image: Image) -> some View {
        let isInUse = toolInUse == tool
        return Button {
            let selection = inkSelection()
            selection.tool = isInUse ? .none : tool
            toolInUse = selection.tool
        } label: {
            Label { Text(title) } icon: { image }
                .padding(4)
                .background(isInUse ? PencilToolbarMetrics.selectedFill : AnyShapeStyle(.clear),
                            in: RoundedRectangle(cornerRadius: GraphiteChrome.cornerRadius, style: .continuous))
        }
        .accessibilityLabel(title)
        .accessibilityValue(isInUse ? "On" : "Off")
        .accessibilityAddTraits(isInUse ? .isSelected : [])
    }
}
#endif
