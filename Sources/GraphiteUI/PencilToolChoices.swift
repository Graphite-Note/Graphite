/**
 * File: PencilToolChoices.swift
 * -----------------------------
 * Layer: UI
 * Description: The Pencil bar's choices of the tool in use apart from its sizes: the eraser's kind, the lasso's type,
 *              the laser's style, the text box's look and the Read Aloud pen's hint.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 04/11/2026
 */

import SwiftUI
import GraphiteCore

#if canImport(UIKit)
/// The tool in use's own choices apart from its sizes: the eraser's kind, the lasso's
/// shape, the laser's style, the text box's look, the Read Aloud pen's hint. An ink has
/// none here; its options open with a second tap on it. On the whole bar they stand beside
/// the tools; on a narrower one they are in its More control.
struct PencilToolChoices: View {
    @Bindable var toolbox: PencilToolbox
    var offersReadAloudPen = false
    var offersTextBoxes = false
    @AppStorage(LassoShape.preferenceKey) private var lassoShape = LassoShape.freehand
    @AppStorage(LaserPointerStyle.preferenceKey) private var laserPointerStyle = LaserPointerStyle.dot

    var body: some View {
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
#endif
