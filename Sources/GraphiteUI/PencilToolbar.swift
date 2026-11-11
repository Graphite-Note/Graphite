/**
 * File: PencilToolbar.swift
 * -------------------------
 * Layer: UI
 * Description: The fixed Pencil bar and its tool row: the whole row, closer and with smaller colors as the bar narrows,
 *              then the least used controls folded into a More control a stage at a time, the writing tools, every color,
 *              the ruler and Add Image staying on the bar, then a condensed form.
 *
 * Authors: Bahey Shalash
 * Version: 0.14
 * Date: 05/11/2026
 */

import SwiftUI
import GraphiteCore

#if canImport(UIKit)
import UIKit
import PencilKit

/// A short stroke in an ink, drawn by PencilKit itself, so the inks are told apart by how
/// they draw rather than by a symbol.
@MainActor
enum PencilInkSample {
    static let size = CGSize(width: 68, height: 30)
    private static let cache = NSCache<NSString, UIImage>()

    static func image(of ink: PencilInk, colorHex: String, colorScheme: ColorScheme, displayScale: CGFloat) -> UIImage {
        let cacheKey = "\(ink.rawValue)|\(colorHex)|\(colorScheme == .dark)|\(displayScale)" as NSString
        if let cachedImage = cache.object(forKey: cacheKey) { return cachedImage }
        // Broad inks are drawn narrower than on a page, to fit the sample, and the finest
        // ones broader, to be seen in it.
        let sampleWidth = CGFloat(min(max(ink.mediumWidth, 2.5), 11))
        let strokeBounds = CGRect(origin: .zero, size: size).insetBy(dx: 9, dy: 0)
        let pointCount = 28
        let points = (0..<pointCount).map { pointIndex in
            let progress = CGFloat(pointIndex) / CGFloat(pointCount - 1)
            let location = CGPoint(x: strokeBounds.minX + strokeBounds.width * progress, y: size.height / 2 - sin(progress * 2 * .pi) * 6)
            // Pressed harder in the middle, as a hand would, which the pen and the pencil show.
            return PKStrokePoint(location: location, timeOffset: TimeInterval(pointIndex) * 0.02, size: CGSize(width: sampleWidth, height: sampleWidth),
                                 opacity: 1, force: 0.6 + 0.8 * sin(progress * .pi), azimuth: .pi / 4, altitude: .pi / 3)
        }
        let stroke = PKStroke(ink: PKInk(ink.inkType, color: UIColor(graphiteHex: colorHex) ?? .black),
                              path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSinceReferenceDate: 0)))
        var sampleImage = UIImage()
        // PencilKit lightens dark inks on a dark background, as the popover's is in dark mode.
        UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light).performAsCurrent {
            sampleImage = PKDrawing(strokes: [stroke]).image(from: CGRect(origin: .zero, size: size), scale: displayScale)
        }
        cache.setObject(sampleImage, forKey: cacheKey)
        return sampleImage
    }
}

/// The fixed tool bar: the tools (`PencilToolRow`) in a row of their own, with the
/// document's own controls at its ends where they have no other place.
struct PencilToolbar<LeadingControls: View, TrailingControls: View>: View {
    @Bindable var toolbox: PencilToolbox
    @Binding var drawsShapes: Bool
    /// Nil where images cannot be added.
    var addImage: (() -> Void)?
    /// The document's history, for the Undo and Redo of the palette Apple Pencil's squeeze opens.
    var undoAvailability: UndoAvailability?
    /// The Read Aloud pen, on PDF pages.
    var offersReadAloudPen = false
    /// The text tool, on PDF pages.
    var offersTextBoxes = false
    /// Called by a tap on the tools while the document is read, which starts writing with
    /// the tool tapped; nil where the bar shows only while writing.
    var beginWriting: (() -> Void)? = nil
    /// The document's own controls, such as Write, Undo and Redo, where they have no
    /// other place: the bar shares its row with them rather than adding one.
    @ViewBuilder var leadingControls: LeadingControls
    @ViewBuilder var trailingControls: TrailingControls

    var body: some View {
        HStack(spacing: 12) {
            leadingControls.padding(.leading, 16)
            PencilToolRow(toolbox: toolbox, drawsShapes: $drawsShapes, addImage: addImage,
                          undoAvailability: undoAvailability, offersReadAloudPen: offersReadAloudPen, offersTextBoxes: offersTextBoxes)
                // With the tool's own action: the tool tapped is the one written with.
                .simultaneousGesture(TapGesture().onEnded { beginWriting?() }, isEnabled: beginWriting != nil)
                .frame(maxWidth: .infinity)
            trailingControls
                .labelStyle(.iconOnly)
                .padding(.trailing, 16)
        }
        .frame(height: PencilToolbarMetrics.height)
        .tint(.primary)
        .background(GraphiteChrome.barBackground)
        .overlay(alignment: .bottom) { Hairline() }
    }
}

/// The fixed bar's tools in one row: the ink presets, the eraser, the lasso, the laser pointer,
/// and on PDF pages the text tool and the Read Aloud pen; the tool's own choices and the three
/// sizes of the ink or eraser in use; black and every favorite color, or for a highlighter its own
/// lighter colors, from Settings › Colors, with Other Color and its plus; then Shapes, the Ruler
/// and Add Image. The row takes the first form that fits (`PencilToolRowLayout`): the whole row,
/// closer and with smaller colors as the bar narrows; then, at the mini size, the least used
/// controls behind one More control a stage at a time (`PencilToolRowLayout.FoldStage`: the
/// laser, text and Read Aloud tools; then the tool's choices, Other Color and Shapes; then Add
/// Image), the tools a person writes with, the sizes, every color and the ruler staying on the
/// bar; then that row with its colors in a strip that scrolls, only where they do not all fit
/// even at the mini size; then fewer tools. Nothing is cut off.
///
/// A second tap on the ink in use opens its options: every ink PencilKit has, any width and
/// opacity, and adding or removing a preset. A second tap on the size in use, of an ink or
/// of the eraser, opens its width, to change it. A long press on a favorite color moves or
/// removes it, and the plus beside Other Color adds the color in use.
///
/// Each tool is its SF Symbol (`PencilToolGlyph`); the tool in use stands on a faint fill and has
/// the selected trait, so it is not told apart by color alone.
struct PencilToolRow: View {
    @Bindable var toolbox: PencilToolbox
    @Binding var drawsShapes: Bool
    /// Nil where images cannot be added.
    var addImage: (() -> Void)?
    /// The document's history, for the Undo and Redo of the palette Apple Pencil's squeeze opens.
    var undoAvailability: UndoAvailability?
    var rowHeight: CGFloat = PencilToolbarMetrics.height
    /// The Read Aloud pen, where there is text to read: on PDF pages.
    var offersReadAloudPen = false
    /// The text tool, on PDF pages.
    var offersTextBoxes = false
    @State private var showsInkOptions = false
    @AppStorage(GraphitePreferences.highlighterPaletteKey) private var storedHighlighterPalette: Data?
    @AppStorage(GraphitePreferences.colorPaletteKey) private var storedColorPalette: Data?
    /// The size whose width is open for changing.
    @State private var adjustedSize: PencilSizeChoice?
    /// The width the row is offered, which sets how many colors a scrolling strip shows.
    @State private var availableWidth: Double = 0

    private typealias Density = PencilToolRowLayout.Density

    var body: some View {
        // The forms in `PencilToolRowLayout`'s order, the first that fits shown. The sizes of the
        // ink or eraser in use stay on the bar in every form but the last two (HUNT-310), and every
        // color and the ruler in every form but the condensed ones (HUNT-317).
        let contents = layoutContents
        ViewThatFits(in: .horizontal) {
            ForEach(PencilToolRowLayout.preferredArrangements, id: \.self) { arrangement in row(arrangement, holding: contents) }
            if let scrollingColors = PencilToolRowLayout.scrollingColorsArrangement(forWidth: availableWidth, holding: contents) {
                row(scrollingColors, holding: contents)
            }
            condensedRow(showing: Int.max, showsSizes: true)
            condensedRow(showing: 6, showsSizes: true)
            condensedRow(showing: 5, showsSizes: true)
            condensedRow(showing: 4, showsSizes: true)
            condensedRow(showing: 3, showsSizes: true)
            condensedRow(showing: 2, showsSizes: true)
            condensedRow(showing: 2, showsSizes: false)
            condensedRow(showing: 1, showsSizes: false)
        }
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: Double.self) { geometry in Double(geometry.size.width) } action: { width in availableWidth = width }
        .frame(height: rowHeight)
        .tint(.primary)
        // Apple's palette answers Apple Pencil's double tap and squeeze; the row takes its place.
        .background { PencilGestureReceiver(toolbox: toolbox, undoAvailability: undoAvailability) }
    }

    /// What the row holds, counted for the scrolling strip's width; the other forms are measured by `ViewThatFits`.
    private var layoutContents: PencilToolRowLayout.Contents {
        PencilToolRowLayout.contents(of: toolbox, favorites: GraphitePreferences.colorPalette(decoding: storedColorPalette),
                                     highlighterColors: GraphitePreferences.highlighterPalette(decoding: storedHighlighterPalette),
                                     offersTextBoxes: offersTextBoxes, offersReadAloudPen: offersReadAloudPen, offersImages: addImage != nil)
    }

    @ViewBuilder private func row(_ arrangement: PencilToolRowLayout.Arrangement, holding contents: PencilToolRowLayout.Contents) -> some View {
        if let placement = PencilToolRowLayout.placement(of: arrangement, holding: contents) {
            placedRow(placement).reportingLayout(placement.hasMoreControl ? .compact : .full, arrangement)
        } else {
            condensedRow(showing: Int.max, showsSizes: true)
        }
    }

    /// The row as `PencilToolRowLayout.placement` sets it: everything on the bar, the form of the 11-inch iPad sideways
    /// (1,194 points) at the regular density and upright (834) closer; or, narrower, at the mini density with the least
    /// used controls behind one More control, a stage at a time. The ink presets, the eraser, the lasso, the tool in
    /// use, the sizes, every color and the ruler are on the bar in every one of these forms.
    private func placedRow(_ placement: PencilToolRowLayout.Placement) -> some View {
        let density = placement.density
        return HStack(spacing: 0) {
            toolButtons(placement.shownTools, density: density)
            if placement.showsToolChoices || placement.showsSizes {
                separator(density)
                if placement.showsToolChoices { toolChoices }
                if placement.showsSizes { sizeButtons(opensWidth: true, density: density) }
            }
            if placement.showsSwatches || placement.showsOtherColor {
                separator(density)
                colorControls(placement)
            }
            separator(density)
            if placement.showsShapes { shapesToggle(density: density) }
            toggleButton("Ruler", symbolName: "ruler", isOn: $toolbox.isRulerActive, density: density)
            if placement.showsAddImage { addImageButton(density: density) }
            if placement.hasMoreControl { moreToolsButton(placement) }
        }
        .padding(.horizontal, density.edgeInset)
    }

    /// The colors the form keeps on the bar: every one, or a strip of whole colors that scrolls, with Other Color and
    /// its plus where the form keeps them.
    @ViewBuilder private func colorControls(_ placement: PencilToolRowLayout.Placement) -> some View {
        if let scrollingSwatchCount = placement.scrollingSwatchCount {
            PencilColorStrip(toolbox: toolbox, rowHeight: rowHeight, visibleSwatchCount: scrollingSwatchCount)
        } else {
            let controls: PencilColorControls = !placement.showsSwatches ? .otherColorAndAdd : placement.showsOtherColor ? .all : .swatches
            PencilColorButtons(toolbox: toolbox, rowHeight: rowHeight, density: placement.density, controls: controls)
        }
    }

    /// The folded row's More control: what the form's fold stage moved off the bar, in the bar's order: the tools used
    /// now and then (the laser pointer, the text tool, the Read Aloud pen), the tool's own choices (the eraser's kind,
    /// the lasso's type), Other Color with its plus, Shapes, and Add Image.
    private func moreToolsButton(_ placement: PencilToolRowLayout.Placement) -> some View {
        PencilBarMoreButton(accessibilityLabel: "More Tools", width: placement.density.toolPitch, rowHeight: rowHeight) { isPresented in
            Image(systemName: drawsShapes || isPresented ? "ellipsis.circle.fill" : "ellipsis.circle")
                .font(.system(size: 17))
        } content: {
            if !placement.foldedTools.isEmpty { toolButtons(placement.foldedTools, density: .regular) }
            if !placement.showsToolChoices { HStack(spacing: 2) { toolChoices } }
            HStack(spacing: 2) {
                if !placement.showsOtherColor, Self.offersColors(toolInUse: toolbox.toolInUse) {
                    PencilColorButtons(toolbox: toolbox, rowHeight: rowHeight, controls: .otherColorAndAdd)
                }
                if !placement.showsShapes { shapesToggle(density: .regular) }
                if !placement.showsAddImage { addImageButton(density: .regular) }
            }
        }
    }

    private func shapesToggle(density: Density) -> some View {
        toggleButton("Shapes", symbolName: drawsShapes ? "square.fill.on.circle.fill" : "square.on.circle", isOn: $drawsShapes, density: density)
    }

    /// The tools, the sizes of the ink or eraser in use, and one control for the tool's other
    /// choices, the colors and the rest, which opens them in a popover: Apple's own way when
    /// a bar has no room for its controls. Where the bar has room for only `shownCount`
    /// tools, the others are in that popover too; where it has no room for the sizes either,
    /// so are they.
    private func condensedRow(showing shownCount: Int, showsSizes: Bool) -> some View {
        let density = Density.tightest
        let tools = PencilToolRowLayout.split(allTools, showing: shownCount, toolInUse: toolInUse)
        return HStack(spacing: 0) {
            toolButtons(tools.shown, density: density)
            separator(density)
            if showsSizes { sizeButtons(opensWidth: true, density: density) }
            condensedOptionsButton(foldedTools: tools.folded, includesSizes: !showsSizes)
        }
        .padding(.horizontal, density.edgeInset)
        .reportingLayout(.condensed, .condensed)
    }

    /// Every tool of the row, in order.
    private var allTools: [PencilToolRowLayout.Tool] {
        PencilToolRowLayout.tools(presetCount: toolbox.presets.count, offersTextBoxes: offersTextBoxes, offersReadAloudPen: offersReadAloudPen)
    }

    /// The tool in use as a tool of the row.
    private var toolInUse: PencilToolRowLayout.Tool? { PencilToolRowLayout.toolInUse(of: toolbox) }

    /// The tool in use's own choices apart from its sizes (`PencilToolChoices`).
    private var toolChoices: some View {
        PencilToolChoices(toolbox: toolbox, offersReadAloudPen: offersReadAloudPen, offersTextBoxes: offersTextBoxes)
    }

    /// Whether the tool in use has the three sizes: an ink or the eraser.
    private var hasSizes: Bool { toolbox.toolInUse == .ink || toolbox.toolInUse == .eraser }

    private func toolButtons(_ tools: [PencilToolRowLayout.Tool], density: Density) -> some View {
        HStack(spacing: 0) {
            ForEach(tools, id: \.self) { tool in toolButton(for: tool, density: density) }
        }
    }

    @ViewBuilder private func toolButton(for tool: PencilToolRowLayout.Tool, density: Density) -> some View {
        let buttons = buttons(density)
        switch tool {
        case .preset(let presetIndex):
            if toolbox.presets.indices.contains(presetIndex) { presetButton(toolbox.presets[presetIndex], at: presetIndex, density: density) }
        case .eraser: buttons.toolButton(.eraser)
        case .lasso: buttons.toolButton(.lasso)
        case .laser: buttons.toolButton(.laser)
        case .text: buttons.toolButton(.text)
        case .readAloud: buttons.toolButton(.readAloud)
        }
    }
    /// The three sizes of the ink or the eraser in use, as dots as wide as they draw: the
    /// thickness control, on the bar beside the tools in every form that has room for it. A
    /// second tap on the size in use opens its width, to change that size (`PencilSizeEditor`),
    /// where `opensWidth`. The eraser shows its sizes while it removes whole strokes too: a
    /// size chosen then erases pixels at that width. Other tools have no width.
    @ViewBuilder private func sizeButtons(opensWidth: Bool, density: Density) -> some View {
        switch toolbox.toolInUse {
        case .ink:
            ForEach(Array(toolbox.presetInUse.widthChoices.enumerated()), id: \.offset) { choiceIndex, width in
                sizeButton(.ink(choiceIndex: choiceIndex), width: width, isChosen: toolbox.chosenWidthIndex == choiceIndex, opensWidth: opensWidth,
                           density: density) {
                    toolbox.useWidthChoice(at: choiceIndex)
                }
            }
        case .eraser:
            ForEach(Array(toolbox.eraserWidthChoices.enumerated()), id: \.offset) { choiceIndex, width in
                sizeButton(.eraser(choiceIndex: choiceIndex), width: width, isChosen: toolbox.chosenEraserWidthIndex == choiceIndex, opensWidth: opensWidth,
                           density: density) {
                    toolbox.useEraserWidthChoice(at: choiceIndex)
                }
                .opacity(toolbox.erasesWholeStrokes ? 0.55 : 1)
                .accessibilityHint(toolbox.erasesWholeStrokes ? "Erases pixels at this width" : "")
            }
        case .lasso, .laser, .text, .readAloud:
            EmptyView()
        }
    }

    @ViewBuilder private func sizeButton(_ size: PencilSizeChoice, width: Double, isChosen: Bool, opensWidth: Bool, density: Density,
                                         choose: @escaping () -> Void) -> some View {
        if opensWidth {
            adjustableSizeButton(size, width: width, isChosen: isChosen, density: density, choose: choose)
        } else {
            buttons(density).sizeButton(choiceIndex: size.choiceIndex, width: width, isChosen: isChosen, choose: choose)
        }
    }

    /// The condensed row's one control for everything after the tools. It shows the ink in
    /// use as a dot of its color and size inside a ring, or the tool's symbol, with a
    /// chevron, so it reads as a control that opens; it opens the rest, and the tools the
    /// bar had no room for.
    private func condensedOptionsButton(foldedTools: [PencilToolRowLayout.Tool], includesSizes: Bool) -> some View {
        PencilBarMoreButton(accessibilityLabel: "Size, Color and More", accessibilityValue: condensedOptionsDescription,
                            width: 44, rowHeight: rowHeight) { isPresented in
            HStack(spacing: 2) {
                condensedOptionsGlyph
                    .frame(width: 24, height: PencilToolbarMetrics.buttonSide)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: PencilToolbarMetrics.buttonSide + 8, height: PencilToolbarMetrics.buttonSide)
            .background(isPresented ? PencilToolbarMetrics.selectedFill : AnyShapeStyle(.clear),
                        in: RoundedRectangle(cornerRadius: GraphiteChrome.cornerRadius, style: .continuous))
        } content: {
            if !foldedTools.isEmpty { toolButtons(foldedTools, density: .regular) }
            HStack(spacing: 2) {
                toolChoices
                // In the popover a size is chosen; its width changes on the bar, or in the ink's options.
                if includesSizes { sizeButtons(opensWidth: false, density: .regular) }
            }
            if Self.offersColors(toolInUse: toolbox.toolInUse) {
                HStack(spacing: 2) { PencilColorButtons(toolbox: toolbox, rowHeight: rowHeight) }
            }
            HStack(spacing: 2) {
                shapesToggle(density: .regular)
                toggleButton("Ruler", symbolName: "ruler", isOn: $toolbox.isRulerActive, density: .regular)
                addImageButton(density: .regular)
            }
        }
    }

    @ViewBuilder private var condensedOptionsGlyph: some View {
        switch toolbox.toolInUse {
        case .ink:
            let diameter = CGFloat(PencilSizeDot.diameter(forWidth: toolbox.presetInUse.width))
            Circle()
                .fill(Color(graphiteHex: toolbox.presetInUse.colorHex) ?? .black)
                .overlay { Circle().strokeBorder(Color.primary.opacity(0.5), lineWidth: 1.5) }
                .frame(width: max(diameter, 14), height: max(diameter, 14))
        default:
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 16))
        }
    }

    private var condensedOptionsDescription: String {
        switch toolbox.toolInUse {
        case .ink: PencilWidthText.millimeters(toolbox.presetInUse.width)
        case .eraser: toolbox.erasesWholeStrokes ? "Strokes" : PencilWidthText.millimeters(toolbox.eraserWidth)
        default: ""
        }
    }

    /// Whether the colors follow the tool's own controls: not for the laser pointer, which
    /// points in its own red, nor for the Read Aloud pen or the text tool, which have their own.
    static func offersColors(toolInUse: PencilToolKind) -> Bool { PencilToolRowLayout.offersColors(toolInUse: toolInUse) }

    /// A hairline between two sections, as wide as the density's room for it.
    private func separator(_ density: Density) -> some View {
        Hairline(axis: .vertical).frame(width: density.separatorWidth, height: 20)
    }

    private func buttons(_ density: Density) -> PencilToolButtons { PencilToolButtons(toolbox: toolbox, rowHeight: rowHeight, density: density) }

    private func presetButton(_ preset: InkPreset, at presetIndex: Int, density: Density) -> some View {
        let isInUse = toolbox.toolInUse == .ink && toolbox.presetInUseIndex == presetIndex
        return buttons(density).presetButton(preset, at: presetIndex) { showsInkOptions = true }
            .popover(isPresented: Binding(get: { showsInkOptions && isInUse }, set: { isPresented in showsInkOptions = isPresented })) {
                PencilInkOptions(toolbox: toolbox)
                    .presentationCompactAdaptation(.popover)
            }
    }

    /// One of the three sizes. A tap on another size draws with it; a second tap on the size
    /// in use opens its width.
    private func adjustableSizeButton(_ size: PencilSizeChoice, width: Double, isChosen: Bool, density: Density, choose: @escaping () -> Void) -> some View {
        buttons(density).sizeButton(choiceIndex: size.choiceIndex, width: width, isChosen: isChosen, opensWidthWhenChosen: true) {
            if isChosen { adjustedSize = size } else { choose() }
        }
        .popover(isPresented: Binding(get: { adjustedSize == size }, set: { isPresented in if !isPresented, adjustedSize == size { adjustedSize = nil } })) {
            PencilSizeEditor(toolbox: toolbox, size: size)
                .presentationCompactAdaptation(.popover)
        }
    }

    /// Shapes or the Ruler: a switch drawn as a tool, on the fill of the tool in use while it is on.
    private func toggleButton(_ title: String, symbolName: String, isOn: Binding<Bool>, density: Density) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            Image(systemName: symbolName)
                .font(.system(size: 16, weight: isOn.wrappedValue ? .semibold : .regular))
                .frame(width: density.toolSide, height: density.toolSide)
                .background(isOn.wrappedValue ? PencilToolbarMetrics.selectedFill : AnyShapeStyle(.clear),
                            in: RoundedRectangle(cornerRadius: GraphiteChrome.cornerRadius, style: .continuous))
                .frame(width: density.toolPitch, height: rowHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isOn.wrappedValue ? "On" : "Off")
    }

    @ViewBuilder private func addImageButton(density: Density) -> some View {
        if let addImage {
            Button("Add Image", systemImage: "photo.badge.plus", action: addImage)
                .labelStyle(.iconOnly)
                .frame(width: density.toolPitch, height: rowHeight)
        }
    }
}

/// Which form of the Pencil tool row is shown: the whole row, at one of three densities; the
/// compact one, folded at one of its stages, with every color and the ruler on the bar and the
/// rest behind one More control, its colors scrolling only where they do not all fit; or the
/// condensed one, with some tools,
/// the colors and the rest behind one control, in a window too narrow even for that.
enum PencilToolRowForm: Equatable {
    case full, compact, condensed

    /// A row on screen: its form, its arrangement, and where it is, in its window's coordinates.
    struct ShownRow {
        let form: PencilToolRowForm
        let arrangement: PencilToolRowLayout.Arrangement
        let frameInWindow: CGRect
        /// Which row reported it, so a row that goes withdraws only its own report.
        fileprivate let reporter: UUID
    }

    /// For tests, which cannot see SwiftUI's views: the row last shown of those still on screen. Setting it to nil
    /// forgets every report, so a test can wait for the next row to show.
    @MainActor static var lastShown: ShownRow? {
        get { shownRows.last }
        set { shownRows = newValue.map { row in [row] } ?? [] }
    }

    /// The rows on screen, the latest report last.
    @MainActor fileprivate static var shownRows: [ShownRow] = []
}

/// Tells tests which form of the row is on screen and where (`PencilToolRowForm.lastShown`): a reader behind the row
/// reports its frame when the row appears and whenever the frame changes, and takes it back when the row goes. A change
/// of the row's geometry alone missed the row that `ViewThatFits` put on screen in place of another, and on the owner's
/// iPad (2026-11-05) a folded row that had left the screen stayed in `lastShown` while the screen showed the whole row
/// (HUNT-317). A row that goes withdraws only its own report, and the latest report of a row still shown takes its
/// place: SwiftUI shows a new row before the one it replaces disappears, and a window of 507 points (2026-11-11) showed
/// two at once, so the row that went took the report of the row left on screen with it.
private struct PencilToolRowLayoutReport: ViewModifier {
    let form: PencilToolRowForm
    let arrangement: PencilToolRowLayout.Arrangement
    /// Which row this is, to tell its report from another's.
    @State private var reporterIdentifier = UUID()

    func body(content: Content) -> some View {
        content.background {
            GeometryReader { geometry in
                let frame = geometry.frame(in: .global)
                Color.clear
                    .onAppear { report(frame) }
                    .onChange(of: frame) { _, changedFrame in report(changedFrame) }
                    .onDisappear { withdraw() }
            }
        }
    }

    private func report(_ frame: CGRect) {
        PencilToolRowForm.shownRows.removeAll { row in row.reporter == reporterIdentifier }
        PencilToolRowForm.shownRows.append(PencilToolRowForm.ShownRow(form: form, arrangement: arrangement, frameInWindow: frame, reporter: reporterIdentifier))
    }

    private func withdraw() {
        PencilToolRowForm.shownRows.removeAll { row in row.reporter == reporterIdentifier }
    }
}

private extension View {
    func reportingLayout(_ form: PencilToolRowForm, _ arrangement: PencilToolRowLayout.Arrangement) -> some View {
        modifier(PencilToolRowLayoutReport(form: form, arrangement: arrangement))
    }
}

extension PencilToolbar where LeadingControls == EmptyView, TrailingControls == EmptyView {
    init(toolbox: PencilToolbox, drawsShapes: Binding<Bool>, addImage: (() -> Void)? = nil, undoAvailability: UndoAvailability? = nil,
         offersReadAloudPen: Bool = false, offersTextBoxes: Bool = false, beginWriting: (() -> Void)? = nil) {
        self.init(toolbox: toolbox, drawsShapes: drawsShapes, addImage: addImage, undoAvailability: undoAvailability,
                  offersReadAloudPen: offersReadAloudPen, offersTextBoxes: offersTextBoxes, beginWriting: beginWriting,
                  leadingControls: { EmptyView() }, trailingControls: { EmptyView() })
    }
}
#endif
