/**
 * File: NoteSlideView.swift
 * -------------------------
 * Layer: UI
 * Description: One slide of a presented note, drawn by the reading view's blocks on the presentation's fixed
 *              canvas, centred, shrunk when taller than the canvas, and scaled to the space it is given.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import SwiftUI
import GraphiteCore

/// A slide scaled to fit the space it is given, keeping the canvas's shape, with bars of the slide's background
/// around it where the space has another shape. The layout inside is the canvas's whatever the size, so the same
/// slide on the device and on an external display has its words in the same places.
struct NoteSlideView: View {
    let content: PresentedSlideContent?
    let root: URL
    @Environment(\.noteTheme) private var theme

    var body: some View {
        GeometryReader { geometry in
            let canvasSize = NotePresentation.canvasSize
            let scale = Self.scale(fitting: canvasSize, in: geometry.size)
            NoteSlideCanvas(content: content, root: root)
                .frame(width: canvasSize.width, height: canvasSize.height)
                .scaleEffect(scale)
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background { NoteSlideBackground(theme: theme) }
    }

    /// The scale that fits `canvasSize` inside `space` whole, keeping its shape.
    static func scale(fitting canvasSize: CGSize, in space: CGSize) -> CGFloat {
        guard canvasSize.width > 0, canvasSize.height > 0, space.width > 0, space.height > 0 else { return 1 }
        return min(space.width / canvasSize.width, space.height / canvasSize.height)
    }

    /// Where the canvas is drawn inside `space`, in the space's coordinates: what the Pencil's marks are placed by.
    static func canvasFrame(in space: CGSize) -> CGRect {
        let canvasSize = NotePresentation.canvasSize
        let scale = scale(fitting: canvasSize, in: space)
        let size = CGSize(width: canvasSize.width * scale, height: canvasSize.height * scale)
        return CGRect(x: (space.width - size.width) / 2, y: (space.height - size.height) / 2, width: size.width, height: size.height)
    }
}

/// The slide's background: the vault theme's, or the window's.
private struct NoteSlideBackground: View {
    let theme: NoteThemeStyle?

    var body: some View {
        if let background = theme?.background { Color(background) } else { windowBackground }
    }

    private var windowBackground: Color {
        #if canImport(UIKit)
        Color(uiColor: .systemBackground)
        #else
        Color(nsColor: .textBackgroundColor)
        #endif
    }
}

/// The slide at the canvas's size: its blocks in a column inside the margins, centred, and shrunk as a whole
/// when they are taller than the column, so nothing scrolls during a talk (decision 3).
struct NoteSlideCanvas: View {
    let content: PresentedSlideContent?
    let root: URL
    /// The height of the blocks at full size, measured as they are laid out.
    @State private var contentHeight: CGFloat = 0

    static let horizontalMargin: CGFloat = 72
    static let verticalMargin: CGFloat = 48
    static var columnWidth: CGFloat { NotePresentation.canvasSize.width - 2 * horizontalMargin }
    static var columnHeight: CGFloat { NotePresentation.canvasSize.height - 2 * verticalMargin }
    /// The gap between blocks, the reading view's at the slide's text size.
    static let blockSpacing: CGFloat = 18

    /// The share of its height a slide is drawn at: 1 when it fits the column, less when it is taller.
    static func fittingScale(contentHeight: CGFloat, columnHeight: CGFloat) -> CGFloat {
        guard contentHeight > columnHeight, contentHeight > 0 else { return 1 }
        return columnHeight / contentHeight
    }

    var body: some View {
        ZStack {
            switch content {
            case .built(let blocks):
                blocksColumn(blocks)
            case .failed:
                Text("This slide could not be drawn.").font(.system(size: NotePresentation.slideTextSize)).foregroundStyle(.secondary)
            case .building, nil:
                ProgressView()
            }
        }
        .frame(width: NotePresentation.canvasSize.width, height: NotePresentation.canvasSize.height)
        .clipped()
    }

    private func blocksColumn(_ blocks: [RenderedBlock]) -> some View {
        VStack(alignment: .leading, spacing: Self.blockSpacing) {
            ReadingBlocksView(blocks: blocks, root: root, textSize: NotePresentation.slideTextSize,
                              navigate: { _, _ in }, scrollToHeading: { _ in }, openPDF: { _, _ in }, updateProperties: nil)
        }
        .frame(width: Self.columnWidth, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { geometry in geometry.size.height } action: { height in contentHeight = height }
        .scaleEffect(Self.fittingScale(contentHeight: contentHeight, columnHeight: Self.columnHeight))
        .slideEnvironment(columnWidth: Self.columnWidth)
    }
}

extension View {
    /// The environment a slide's blocks are drawn in: drawn rather than selectable, with nothing that scrolls
    /// (code and wide tables wrap), diagrams as shapes that stay sharp at any scale, and web frames as boxes.
    func slideEnvironment(columnWidth: CGFloat) -> some View {
        self
            .environment(\.readingIsPrinted, true)
            .environment(\.webFramePresentation, .printed)
            .environment(\.embeddedImageColumnWidth, columnWidth)
    }
}
