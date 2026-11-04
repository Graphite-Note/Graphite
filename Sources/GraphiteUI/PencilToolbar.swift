/**
 * File: PencilToolbar.swift
 * -------------------------
 * Layer: UI
 * Description: The fixed Pencil bar and its tool row, which folds into a compact and a condensed form instead of
 *              scrolling.
 *
 * Authors: Bahey Shalash
 * Version: 0.11
 * Date: 04/11/2026
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

/// The fixed bar's tools in one row: the ink presets, the eraser and the lasso; the width of
/// the tool in use; its color, from the favorite colors of Settings › Colors, or for a
/// highlighter from its own lighter colors there; then the shape tool, the ruler, and adding
/// an image. The row takes the width it needs where that fits and folds where it does not
/// (`body`), never scrolling. The fixed bar shows it, in a row of its own, centered.
///
/// A second tap on the ink in use opens its options: every ink PencilKit has, any width and
/// opacity, and adding or removing a preset. A second tap on the size in use, of an ink or
/// of the eraser, opens its width, to change it. A long press on a favorite color moves or
/// removes it, and the plus beside Other Color adds the color in use.
///
/// The inks, the eraser and the lasso are drawn standing upright, as in Apple's palette,
/// each ink's tip in its color; the tool in use stands raised and has the selected trait,
/// so it is not told apart by color alone.
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
    @AppStorage(LassoShape.preferenceKey) private var lassoShape = LassoShape.freehand
    @AppStorage(LaserPointerStyle.preferenceKey) private var laserPointerStyle = LaserPointerStyle.dot
    /// The size whose width is open for changing.
    @State private var adjustedSize: PencilSizeChoice?

    private var buttonSide: CGFloat { PencilToolbarMetrics.buttonSide }
    private var selectedFill: AnyShapeStyle { PencilToolbarMetrics.selectedFill }

    /// How much of the row shows, by the width it has (`PencilToolRowLayout`).
    @State private var showsCompactOptions = false

    var body: some View {
        // The whole row where it fits. Narrower, the row folds one thing at a time and keeps
        // the rest: first Shapes and Ruler into one menu, then the colors behind one well of
        // the color in use, then the tool's other choices and the colors behind one control.
        // The sizes of the ink or eraser in use stay on the bar in every form but the last
        // two, so a thickness is always one tap away (HUNT-310); only in a window too narrow
        // for every tool do the tools that do not fit join the rest behind that control, the
        // tool in use always staying on the bar. Nothing is cut off and nothing scrolls.
        ViewThatFits(in: .horizontal) {
            fullRow(foldsToggles: false)
                .reportingLayout(.full)
            fullRow(foldsToggles: true)
                .reportingLayout(.full)
            rowWithColorWell
                .reportingLayout(.colorWell)
            condensedRow(showing: Int.max, showsSizes: true)
            condensedRow(showing: 6, showsSizes: true)
            condensedRow(showing: 5, showsSizes: true)
            condensedRow(showing: 4, showsSizes: true)
            condensedRow(showing: 3, showsSizes: true)
            condensedRow(showing: 2, showsSizes: true)
            condensedRow(showing: 2, showsSizes: false)
            condensedRow(showing: 1, showsSizes: false)
        }
        .frame(height: rowHeight)
        .tint(.primary)
        // Apple's palette answers Apple Pencil's double tap and squeeze; the row takes its place.
        .background { PencilGestureReceiver(toolbox: toolbox, undoAvailability: undoAvailability) }
    }

    private func fullRow(foldsToggles: Bool) -> some View {
        HStack(spacing: 2) {
            toolButtons(allTools)
            separator
            toolChoices
            sizeButtons(opensWidth: true)
            separator
            if Self.offersColors(toolInUse: toolbox.toolInUse) {
                colorButtons
                separator
            }
            if foldsToggles { foldedExtraButtons } else { extraButtons }
        }
        .padding(.horizontal, 10)
    }

    /// Every tool, the tool's own choices and sizes, and the colors behind one well of the
    /// color in use: the form of an 11-inch iPad, whose bar is 834 points wide upright and
    /// about 870 beside the sidebar in landscape, too narrow for the colors and the tools in
    /// one row.
    private var rowWithColorWell: some View {
        HStack(spacing: 2) {
            toolButtons(allTools)
            separator
            toolChoices
            sizeButtons(opensWidth: true)
            separator
            if Self.offersColors(toolInUse: toolbox.toolInUse) {
                colorWell
                separator
            }
            foldedExtraButtons
        }
        .padding(.horizontal, 10)
    }

    /// The tools, the sizes of the ink or eraser in use, and one control for the tool's other
    /// choices, the colors and the rest, which opens them in a popover: Apple's own way when
    /// a bar has no room for its controls. Where the bar has room for only `shownCount`
    /// tools, the others are in that popover too; where it has no room for the sizes either,
    /// so are they.
    private func condensedRow(showing shownCount: Int, showsSizes: Bool) -> some View {
        let tools = PencilToolRowLayout.split(allTools, showing: shownCount, toolInUse: toolInUse)
        return HStack(spacing: 2) {
            toolButtons(tools.shown)
            separator
            if showsSizes { sizeButtons(opensWidth: true) }
            compactOptionsButton(foldedTools: tools.folded, includesSizes: !showsSizes)
        }
        .padding(.horizontal, 10)
        .reportingLayout(tools.folded.isEmpty && showsSizes ? .compact : .condensed)
    }

    /// Every tool of the row, in order.
    private var allTools: [PencilToolRowLayout.Tool] {
        PencilToolRowLayout.tools(presetCount: toolbox.presets.count, offersTextBoxes: offersTextBoxes, offersReadAloudPen: offersReadAloudPen)
    }

    /// The tool in use as a tool of the row; nil for one the row does not have.
    private var toolInUse: PencilToolRowLayout.Tool? {
        switch toolbox.toolInUse {
        case .ink: .preset(index: toolbox.presetInUseIndex)
        case .eraser: .eraser
        case .lasso: .lasso
        case .laser: .laser
        case .text: .text
        case .readAloud: .readAloud
        }
    }

    private func toolButtons(_ tools: [PencilToolRowLayout.Tool]) -> some View {
        HStack(spacing: 2) {
            ForEach(tools, id: \.self) { tool in toolButton(for: tool) }
        }
    }

    @ViewBuilder private func toolButton(for tool: PencilToolRowLayout.Tool) -> some View {
        switch tool {
        case .preset(let presetIndex):
            if toolbox.presets.indices.contains(presetIndex) { presetButton(toolbox.presets[presetIndex], at: presetIndex) }
        case .eraser: toolButton(.eraser)
        case .lasso: toolButton(.lasso)
        case .laser: toolButton(.laser)
        case .text: toolButton(.text)
        case .readAloud: toolButton(.readAloud)
        }
    }

    /// The tool in use's own choices apart from its sizes: the eraser's kind, the lasso's
    /// shape, the laser's style, the text box's look, the Read Aloud pen's hint. An ink has
    /// none here; its options open with a second tap on it.
    @ViewBuilder private var toolChoices: some View {
        switch toolbox.toolInUse {
        case .ink:
            EmptyView()
        case .eraser:
            Picker("Eraser", selection: $toolbox.erasesWholeStrokes) {
                Text("Strokes").tag(true)
                Text("Pixels").tag(false)
            }
            .pickerStyle(.segmented)
            .fixedSize()
        case .lasso:
            // Remembered for every canvas, as Goodnotes keeps its lasso's type.
            Picker("Lasso Type", selection: $lassoShape) {
                ForEach(LassoShape.allCases) { shape in Text(shape.title).tag(shape) }
            }
            .pickerStyle(.segmented)
            .fixedSize()
        case .laser:
            Picker("Laser Pointer", selection: $laserPointerStyle) {
                ForEach(LaserPointerStyle.allCases) { style in Text(style.title).tag(style) }
            }
            .pickerStyle(.segmented)
            .fixedSize()
        case .text:
            PencilTextToolOptions(offersTextBoxes: offersTextBoxes)
        case .readAloud:
            Text(offersReadAloudPen ? "Tap a word to read; tap another to stop there" : "Nothing to read here")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
        }
    }

    /// The three sizes of the ink or the eraser in use, as dots as wide as they draw: the
    /// thickness control, on the bar beside the tools in every form that has room for it. A
    /// second tap on the size in use opens its width, to change that size (`PencilSizeEditor`),
    /// where `opensWidth`. The eraser shows its sizes while it removes whole strokes too: a
    /// size chosen then erases pixels at that width. Other tools have no width.
    @ViewBuilder private func sizeButtons(opensWidth: Bool) -> some View {
        switch toolbox.toolInUse {
        case .ink:
            ForEach(Array(toolbox.presetInUse.widthChoices.enumerated()), id: \.offset) { choiceIndex, width in
                sizeButton(.ink(choiceIndex: choiceIndex), width: width, isChosen: toolbox.chosenWidthIndex == choiceIndex, opensWidth: opensWidth) {
                    toolbox.useWidthChoice(at: choiceIndex)
                }
            }
        case .eraser:
            ForEach(Array(toolbox.eraserWidthChoices.enumerated()), id: \.offset) { choiceIndex, width in
                sizeButton(.eraser(choiceIndex: choiceIndex), width: width, isChosen: toolbox.chosenEraserWidthIndex == choiceIndex, opensWidth: opensWidth) {
                    toolbox.useEraserWidthChoice(at: choiceIndex)
                }
                .opacity(toolbox.erasesWholeStrokes ? 0.55 : 1)
                .accessibilityHint(toolbox.erasesWholeStrokes ? "Erases pixels at this width" : "")
            }
        case .lasso, .laser, .text, .readAloud:
            EmptyView()
        }
    }

    @ViewBuilder private func sizeButton(_ size: PencilSizeChoice, width: Double, isChosen: Bool, opensWidth: Bool, choose: @escaping () -> Void) -> some View {
        if opensWidth {
            adjustableSizeButton(size, width: width, isChosen: isChosen, choose: choose)
        } else {
            buttons.sizeButton(choiceIndex: size.choiceIndex, width: width, isChosen: isChosen, choose: choose)
        }
    }

    /// The colors of the ink in use, with their editing (`PencilColorButtons`).
    private var colorButtons: some View { PencilColorButtons(toolbox: toolbox, rowHeight: rowHeight) }

    /// The color in use as one well that opens the colors (`PencilColorWell`).
    private var colorWell: some View { PencilColorWell(toolbox: toolbox, rowHeight: rowHeight) }

    /// Shapes and Ruler as one menu, then Add Image: the extra buttons in one button's less room.
    @ViewBuilder private var foldedExtraButtons: some View {
        Menu {
            Toggle("Draw Shapes", systemImage: "square.on.circle", isOn: $drawsShapes)
            Toggle("Ruler", systemImage: "ruler", isOn: $toolbox.isRulerActive)
        } label: {
            Image(systemName: drawsShapes || toolbox.isRulerActive ? "ellipsis.circle.fill" : "ellipsis.circle")
                .frame(width: buttonSide, height: rowHeight)
        }
        .menuIndicator(.hidden)
        .accessibilityLabel("Shapes and Ruler")
        if let addImage {
            Button("Add Image", systemImage: "photo.badge.plus", action: addImage)
                .labelStyle(.iconOnly)
                .frame(width: buttonSide, height: rowHeight)
        }
    }

    @ViewBuilder private var extraButtons: some View {
        toggleButton("Shapes", symbolName: drawsShapes ? "square.fill.on.circle.fill" : "square.on.circle", isOn: $drawsShapes)
        toggleButton("Ruler", symbolName: "ruler", isOn: $toolbox.isRulerActive)
        if let addImage {
            Button("Add Image", systemImage: "photo.badge.plus", action: addImage)
                .labelStyle(.iconOnly)
                .frame(width: buttonSide, height: rowHeight)
        }
    }

    /// The compact row's one control for everything after the tools. It shows the ink in
    /// use as a dot of its color and size inside a ring, or the tool's symbol, with a
    /// chevron, so it reads as a control that opens; it opens the rest, and the tools the
    /// bar had no room for.
    private func compactOptionsButton(foldedTools: [PencilToolRowLayout.Tool], includesSizes: Bool) -> some View {
        Button {
            showsCompactOptions = true
        } label: {
            HStack(spacing: 2) {
                compactOptionsGlyph
                    .frame(width: 24, height: buttonSide)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: buttonSide + 8, height: buttonSide)
            .background(showsCompactOptions ? selectedFill : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: GraphiteChrome.cornerRadius, style: .continuous))
            .frame(width: 44, height: rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Size, Color and More")
        .accessibilityValue(compactOptionsDescription)
        .popover(isPresented: $showsCompactOptions) {
            VStack(alignment: .leading, spacing: 4) {
                if !foldedTools.isEmpty { toolButtons(foldedTools) }
                HStack(spacing: 2) {
                    toolChoices
                    // In the popover a size is chosen; its width changes on the bar, or in the ink's options.
                    if includesSizes { sizeButtons(opensWidth: false) }
                }
                if Self.offersColors(toolInUse: toolbox.toolInUse) {
                    HStack(spacing: 2) { colorButtons }
                }
                HStack(spacing: 2) { extraButtons }
            }
            .padding(12)
            .tint(.primary)
            .presentationCompactAdaptation(.popover)
        }
    }

    @ViewBuilder private var compactOptionsGlyph: some View {
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

    private var compactOptionsDescription: String {
        switch toolbox.toolInUse {
        case .ink: PencilWidthText.millimeters(toolbox.presetInUse.width)
        case .eraser: toolbox.erasesWholeStrokes ? "Strokes" : PencilWidthText.millimeters(toolbox.eraserWidth)
        default: ""
        }
    }

    /// Whether the colors follow the tool's own controls: not for the laser pointer, which
    /// points in its own red and whose only choice is Dot or Line.
    static func offersColors(toolInUse: PencilToolKind) -> Bool { toolInUse != .laser && toolInUse != .readAloud && toolInUse != .text }

    private var separator: some View {
        Hairline(axis: .vertical).frame(height: 20).padding(.horizontal, 6)
    }

    private var buttons: PencilToolButtons { PencilToolButtons(toolbox: toolbox, rowHeight: rowHeight) }

    private func presetButton(_ preset: InkPreset, at presetIndex: Int) -> some View {
        let isInUse = toolbox.toolInUse == .ink && toolbox.presetInUseIndex == presetIndex
        return buttons.presetButton(preset, at: presetIndex) { showsInkOptions = true }
            .popover(isPresented: Binding(get: { showsInkOptions && isInUse }, set: { isPresented in showsInkOptions = isPresented })) {
                PencilInkOptions(toolbox: toolbox)
                    .presentationCompactAdaptation(.popover)
            }
    }

    private func toolButton(_ kind: PencilToolKind) -> some View { buttons.toolButton(kind) }

    /// One of the three sizes. A tap on another size draws with it; a second tap on the size
    /// in use opens its width.
    private func adjustableSizeButton(_ size: PencilSizeChoice, width: Double, isChosen: Bool, choose: @escaping () -> Void) -> some View {
        buttons.sizeButton(choiceIndex: size.choiceIndex, width: width, isChosen: isChosen, opensWidthWhenChosen: true) {
            if isChosen { adjustedSize = size } else { choose() }
        }
        .popover(isPresented: Binding(get: { adjustedSize == size }, set: { isPresented in if !isPresented, adjustedSize == size { adjustedSize = nil } })) {
            PencilSizeEditor(toolbox: toolbox, size: size)
                .presentationCompactAdaptation(.popover)
        }
    }


    private func toggleButton(_ title: String, symbolName: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            Image(systemName: symbolName)
                .font(.system(size: 16, weight: isOn.wrappedValue ? .semibold : .regular))
                .frame(width: buttonSide, height: buttonSide)
                .background(isOn.wrappedValue ? selectedFill : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: GraphiteChrome.cornerRadius, style: .continuous))
                .frame(height: rowHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isOn.wrappedValue ? "On" : "Off")
    }
}

/// Which form of the Pencil tool row is shown: the whole row; every tool and size with the
/// colors behind one well; the compact one, the tools and sizes with the rest behind one
/// control; or the condensed one, with some tools behind that control, in a window too
/// narrow even for that. None of them scrolls.
enum PencilToolRowForm: Equatable {
    case full, colorWell, compact, condensed

    /// For tests, which cannot see SwiftUI's views: the form last shown, and where, in its
    /// window's coordinates.
    @MainActor static var lastShown: (form: PencilToolRowForm, frameInWindow: CGRect)?
}

/// The text tool's options on the bar: the look of the next new text box, where there is a
/// page to put it on.
struct PencilTextToolOptions: View {
    let offersTextBoxes: Bool
    /// The look of the next new text box, which these options change.
    @AppStorage(PDFTextBoxDefaults.preferenceKey) private var storedTextBoxDefaults: Data?

    var body: some View {
        if offersTextBoxes {
            let defaults = PDFTextBoxDefaults.stored(decoding: storedTextBoxDefaults)
            PDFTextFormatControls(attributes: defaults.attributes, style: defaults.boxStyle, apply: { change in
                var changed = defaults
                changed.attributes = change.applied(to: defaults.attributes)
                changed.boxStyle = change.applied(to: defaults.boxStyle, textColor: defaults.attributes.color)
                if let encoded = changed.encoded { storedTextBoxDefaults = encoded }
            }, isCompact: true)
        } else {
            Text("Text boxes go on PDF pages")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
        }
    }
}

private extension View {
    func reportingLayout(_ form: PencilToolRowForm) -> some View {
        onGeometryChange(for: CGRect.self) { geometry in geometry.frame(in: .global) } action: { frame in
            PencilToolRowForm.lastShown = (form, frame)
        }
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
