/**
 * File: PencilToolButtons.swift
 * -----------------------------
 * Layer: UI
 * Description: The buttons of the Pencil bar's tools, sizes and colors, shared by the fixed bar and the squeeze
 *              palette.
 *
 * Authors: Bahey Shalash
 * Version: 0.9
 * Date: 05/11/2026
 */

import SwiftUI
import GraphiteCore

#if canImport(UIKit)
import UIKit
import PencilKit

/// The buttons of the bar's tools, shared by the fixed bar and the palette Apple Pencil's
/// squeeze opens. Each is as wide as the bar's density sets (`PencilToolRowLayout.Density`)
/// and touched over the row's whole height.
@MainActor
struct PencilToolButtons {
    let toolbox: PencilToolbox
    let rowHeight: CGFloat
    var density: PencilToolRowLayout.Density = .regular

    private var selectedFill: AnyShapeStyle { PencilToolbarMetrics.selectedFill }

    /// An ink preset; a tap on the one in use calls `tapOnPresetInUse`.
    func presetButton(_ preset: InkPreset, at presetIndex: Int, tapOnPresetInUse: @escaping () -> Void) -> some View {
        let isInUse = toolbox.toolInUse == .ink && toolbox.presetInUseIndex == presetIndex
        return Button {
            if isInUse { tapOnPresetInUse() } else { toolbox.usePreset(at: presetIndex) }
        } label: {
            glyphLabel(PencilToolGlyph(tool: .ink(preset.ink), inkHex: preset.colorHex, inkOpacity: preset.opacity, isInUse: isInUse,
                                       side: density.toolSide))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(preset.ink.title)
        .accessibilityHint(isInUse ? "Opens the ink's options" : "")
        .accessibilityAddTraits(isInUse ? .isSelected : [])
    }

    func toolButton(_ kind: PencilToolKind) -> some View {
        let isInUse = toolbox.toolInUse == kind
        return Button {
            toolbox.use(kind)
        } label: {
            glyphLabel(PencilToolGlyph(tool: PencilToolGlyph.Tool(kind: kind), isInUse: isInUse, side: density.toolSide))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(kind.title)
        .accessibilityAddTraits(isInUse ? .isSelected : [])
    }

    /// A tool centered in its width, taking touches over the row's whole height.
    private func glyphLabel(_ glyph: PencilToolGlyph) -> some View {
        glyph
            .frame(width: density.toolPitch, height: rowHeight)
            .contentShape(Rectangle())
    }

    /// One of the three sizes, of an ink or of the eraser, as a dot as large as its width
    /// (`PencilSizeDot`). Where a second tap on the size in use opens its width, VoiceOver says so.
    func sizeButton(choiceIndex: Int, width: Double, isChosen: Bool, opensWidthWhenChosen: Bool = false, choose: @escaping () -> Void) -> some View {
        let side = CGFloat(density.sizeSide)
        // The broadest dots are drawn no wider than the button leaves room for.
        let diameter = min(CGFloat(PencilSizeDot.diameter(forWidth: width)), side - 4)
        return Button(action: choose) {
            Circle()
                .fill(.primary)
                .frame(width: diameter, height: diameter)
                .frame(width: side, height: side)
                .background(isChosen ? selectedFill : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: GraphiteChrome.cornerRadius, style: .continuous))
                .frame(width: density.sizePitch, height: rowHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(["Fine", "Medium", "Broad"][min(choiceIndex, 2)])
        .accessibilityValue(PencilWidthText.millimeters(width))
        .accessibilityHint(isChosen && opensWidthWhenChosen ? "Opens its width" : "")
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }

    func colorButton(name: String, hex: String) -> some View {
        let isInUse = isColorInUse(hex: hex)
        return Button {
            toolbox.chooseColor(hex: hex)
        } label: {
            colorSwatch(hex: hex, isInUse: isInUse)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isInUse ? .isSelected : [])
    }

    /// Whether the ink in use draws in this color.
    func isColorInUse(hex: String) -> Bool {
        toolbox.toolInUse == .ink && TextColorMarkup.canonicalHex(hex) == toolbox.presetInUse.colorHex
    }

    /// A color as the bar draws it, ringed when the ink in use draws in it, touched over the swatch's pitch and the
    /// row's height: the squeeze palette's buttons and the bar's arrangeable colors (`PencilColorSwatchRow`).
    func colorSwatch(hex: String, isInUse: Bool) -> some View {
        Circle()
            .fill(Color(graphiteHex: hex) ?? .black)
            // A ring in the text color, so a black ink shows on the dark bar of dark mode: at 60 % it reads at more
            // than 3 to 1 on the bar's darkest gray (WCAG 1.4.11) at every density, the 16-point dots too; at 40 %
            // the owner's iPad measured 2.65 to 1.
            .overlay { Circle().strokeBorder(Color.primary.opacity(0.6), lineWidth: 1) }
            .frame(width: density.swatchDiameter, height: density.swatchDiameter)
            // A ring, so the color in use is marked by shape as well.
            .overlay {
                if isInUse { Circle().strokeBorder(.primary, lineWidth: 2).frame(width: density.swatchRingDiameter, height: density.swatchRingDiameter) }
            }
            .frame(width: density.swatchPitch, height: rowHeight)
            .contentShape(Rectangle())
    }
}

enum PencilToolbarMetrics {
    static let height: CGFloat = 44
    static let buttonSide: CGFloat = 36
    /// The background of the tool in use.
    static var selectedFill: AnyShapeStyle { AnyShapeStyle(Color(PlatformColor.primaryText(opacity: 0.1, increasedContrastOpacity: 0.2))) }
}

/// A tool of the bar as Apple's SF Symbols draw it: the ink's own symbol (`PencilInk.symbolName`),
/// the eraser or the lasso, or the laser pointer's own glyph in their style (`LaserPointerGlyph`), with a short bar in the ink's color under an ink, so the bar shows
/// what each tool draws. The tool in use is drawn at full strength on the bar's faint fill,
/// as the sizes and colors beside it are, so it is marked by more than color.
struct PencilToolGlyph: View {
    enum Tool: Equatable {
        case ink(PencilInk)
        case eraser
        case lasso
        case laser
        case readAloud
        case text

        /// The glyph of a tool other than an ink.
        init(kind: PencilToolKind) {
            switch kind {
            case .eraser, .ink: self = .eraser
            case .lasso: self = .lasso
            case .laser: self = .laser
            case .readAloud: self = .readAloud
            case .text: self = .text
            }
        }
    }

    let tool: Tool
    var inkHex: String = PencilInk.pen.defaultColorHex
    var inkOpacity: Double = 1
    let isInUse: Bool
    /// The side of the faint fill of the tool in use: smaller on a narrow bar (`PencilToolRowLayout.Density.toolSide`).
    var side: Double = PencilToolbarMetrics.buttonSide

    private var symbolName: String {
        switch tool {
        case .ink(let ink): ink.symbolName
        case .eraser: PencilToolKind.eraser.symbolName
        case .lasso: PencilToolKind.lasso.symbolName
        case .laser: PencilToolKind.laser.symbolName
        case .readAloud: PencilToolKind.readAloud.symbolName
        case .text: PencilToolKind.text.symbolName
        }
    }

    private var inkColor: Color? {
        guard case .ink = tool else { return nil }
        // A faint ink, such as a highlighter at low opacity, still shows which color it is.
        return (Color(graphiteHex: inkHex) ?? .black).opacity(max(inkOpacity, 0.45))
    }

    var body: some View {
        VStack(spacing: 3) {
            Group {
                if tool == .laser {
                    LaserPointerGlyph(isInUse: isInUse)
                } else if tool == .readAloud {
                    ReadAloudPenGlyph(isInUse: isInUse)
                } else {
                    Image(systemName: symbolName)
                        .font(.system(size: 17, weight: isInUse ? .semibold : .regular))
                        .foregroundStyle(isInUse ? .primary : .secondary)
                }
            }
            .frame(height: 22)
            Capsule()
                .fill(inkColor ?? .clear)
                .overlay { if inkColor != nil { Capsule().strokeBorder(Color.primary.opacity(0.4), lineWidth: 0.5) } }
                .frame(width: 16, height: 3)
        }
        .frame(width: side, height: side)
        .background(isInUse ? PencilToolbarMetrics.selectedFill : AnyShapeStyle(.clear),
                    in: RoundedRectangle(cornerRadius: GraphiteChrome.cornerRadius, style: .continuous))
        .accessibilityHidden(true)
    }
}
#endif
