/**
 * File: PDFMarkupRowOptions.swift
 * -------------------------------
 * Layer: UI
 * Description: The choices the Mac's markup row shows for its chosen tool: the Draw tool's colours and line widths,
 *              and the Text Box tool's font, size, faces, colour, alignment, fill and border, laid out in the row or
 *              folded into menus where the pane is narrow.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 13/11/2026
 */

#if os(macOS)
import SwiftUI
import AppKit
import GraphiteCore
import GraphiteApple

extension Color {
    /// A text or ink colour of a PDF page, as the iPad's format controls make it.
    init(textColor: PDFTextColor) {
        self.init(.sRGB, red: textColor.red, green: textColor.green, blue: textColor.blue)
    }
}

/// The colours the row offers for ink and text: black, then the favourite colours of Settings › Colors.
enum PDFMarkupRowColors {
    static func choices(storedPalette: Data?) -> [(name: String, color: PDFTextColor)] {
        [("Black", .black)] + GraphitePreferences.colorPalette(decoding: storedPalette).compactMap { favorite in
            PDFTextColor(hex: favorite.hex).map { color in (favorite.name.capitalized, color) }
        }
    }
}

/// Images for the labels of the row's folded menus, which AppKit draws from an image, not
/// from a SwiftUI shape: made as images, they keep their colour, and their edge follows the
/// appearance, so black shows on a dark row.
enum PDFMarkupRowImages {
    private static let side: CGFloat = 14
    private static let edgeOpacity: CGFloat = 0.45
    private static let lineLength: CGFloat = 16

    static func swatch(_ color: PDFTextColor) -> NSImage {
        NSImage(size: NSSize(width: side, height: side), flipped: false) { rectangle in
            NSColor(srgbRed: CGFloat(color.red), green: CGFloat(color.green), blue: CGFloat(color.blue), alpha: 1).setFill()
            NSBezierPath(ovalIn: rectangle.insetBy(dx: 0.5, dy: 0.5)).fill()
            NSColor.labelColor.withAlphaComponent(edgeOpacity).setStroke()
            NSBezierPath(ovalIn: rectangle.insetBy(dx: 0.5, dy: 0.5)).stroke()
            return true
        }
    }

    static func line(_ width: PDFMarkupInkWidth) -> NSImage {
        NSImage(size: NSSize(width: lineLength, height: side), flipped: false) { rectangle in
            let thickness = max(1, CGFloat(width.points))
            NSColor.labelColor.setFill()
            NSBezierPath(roundedRect: NSRect(x: 0, y: (rectangle.height - thickness) / 2, width: rectangle.width, height: thickness),
                         xRadius: thickness / 2, yRadius: thickness / 2).fill()
            return true
        }
    }
}

/// The Draw tool's colours and line widths: swatches and width buttons in a wide row, one
/// menu each in a narrow one.
struct PDFMarkupInkOptions: View {
    @Binding var inkStyle: PDFMarkupInkStyle
    let isFolded: Bool
    @AppStorage(GraphitePreferences.colorPaletteKey) private var storedColorPalette: Data?

    var body: some View {
        HStack(spacing: PDFMarkupRowMetrics.itemSpacing) {
            if isFolded {
                colorMenu
                widthMenu
            } else {
                ForEach(PDFMarkupRowColors.choices(storedPalette: storedColorPalette), id: \.name) { choice in colorButton(choice.name, choice.color) }
                Divider().frame(height: PDFMarkupRowMetrics.dividerHeight).padding(.horizontal, 4)
                ForEach(PDFMarkupInkWidth.allCases) { width in widthButton(width) }
            }
        }
    }

    private func colorButton(_ name: String, _ color: PDFTextColor) -> some View {
        let isInUse = inkStyle.color == color
        return Button { inkStyle.color = color } label: {
            PDFMarkupSwatch(color: Color(textColor: color), isInUse: isInUse)
        }
        .buttonStyle(.plain)
        .help("Ink \(name)")
        .accessibilityLabel("Ink \(name)")
        .accessibilityAddTraits(isInUse ? .isSelected : [])
    }

    private var colorMenu: some View {
        Menu {
            ForEach(PDFMarkupRowColors.choices(storedPalette: storedColorPalette), id: \.name) { choice in
                Button(choice.name) { inkStyle.color = choice.color }
            }
        } label: {
            Image(nsImage: PDFMarkupRowImages.swatch(inkStyle.color))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("Ink Color")
    }

    private func widthButton(_ width: PDFMarkupInkWidth) -> some View {
        let isInUse = inkStyle.width == width
        return Button { inkStyle.width = width } label: {
            Self.widthSample(width)
                .frame(width: PDFMarkupRowMetrics.toolSide, height: PDFMarkupRowMetrics.toolSide)
                .background(PDFMarkupRowMetrics.chosenBackground(isInUse))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(width.title) Line")
        .accessibilityLabel("\(width.title) Line")
        .accessibilityAddTraits(isInUse ? .isSelected : [])
    }

    private var widthMenu: some View {
        Menu {
            ForEach(PDFMarkupInkWidth.allCases) { width in Button("\(width.title) Line") { inkStyle.width = width } }
        } label: {
            Image(nsImage: PDFMarkupRowImages.line(inkStyle.width))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("Line Width")
    }

    /// A short line as thick as the width, at most the row's room.
    private static let sampleLength: CGFloat = 14
    private static func widthSample(_ width: PDFMarkupInkWidth) -> some View {
        Capsule().fill(Color.primary).frame(width: sampleLength, height: max(1, CGFloat(width.points)))
    }
}

/// What the Text Box tool's controls format: the box selected or typed in, through the
/// PDF view's text box tool, or, with none, the look the next new box takes.
struct PDFMarkupTextFormatSource {
    /// The format of the box selected or typed in; nil while none is.
    let boxFormat: PDFTextBoxDefaults?
    /// Formats the box selected or typed in; nil while none is.
    let applyToBox: ((PDFTextBoxFormatChange) -> Void)?

    init(boxFormat: PDFTextBoxDefaults?, applyToBox: ((PDFTextBoxFormatChange) -> Void)?) {
        self.boxFormat = boxFormat
        self.applyToBox = applyToBox
    }

    @MainActor init(session: PDFSession) {
        boxFormat = session.textBoxFormat
        applyToBox = session.textBoxActivity == .idle ? nil : session.applyTextBoxFormat
    }
}

/// The Text Box tool's format controls in the row: font, size, bold, italic and underline,
/// colour, alignment, fill and border. They format the box selected or typed in, or, with
/// none, the next new box, whose look is kept on the device (`PDFTextBoxDefaults`).
struct PDFMarkupTextFormatControls: View {
    let source: PDFMarkupTextFormatSource
    let isFolded: Bool
    @AppStorage(PDFTextBoxDefaults.preferenceKey) private var storedDefaults: Data?
    @AppStorage(GraphitePreferences.colorPaletteKey) private var storedColorPalette: Data?

    private var format: PDFTextBoxDefaults { source.boxFormat ?? PDFTextBoxDefaults.stored(decoding: storedDefaults) }

    var body: some View {
        HStack(spacing: PDFMarkupRowMetrics.groupSpacing) {
            fontMenu
            sizeMenu
            faceButtons
            colorMenu
            if isFolded {
                paragraphMenu
            } else {
                alignmentPicker
                fillMenu
                borderToggle
            }
        }
        .controlSize(.small)
    }

    private func apply(_ change: PDFTextBoxFormatChange) {
        if let applyToBox = source.applyToBox {
            applyToBox(change)
            return
        }
        let current = PDFTextBoxDefaults.stored(decoding: storedDefaults)
        let changed = PDFTextBoxDefaults(attributes: change.applied(to: current.attributes),
                                         boxStyle: change.applied(to: current.boxStyle, textColor: current.attributes.color))
        if let encoded = changed.encoded { storedDefaults = encoded }
    }

    private var fontMenu: some View {
        Menu {
            let families = PDFTextBoxFonts.offeredFamilies.contains(format.attributes.fontFamily)
                ? PDFTextBoxFonts.offeredFamilies : [format.attributes.fontFamily] + PDFTextBoxFonts.offeredFamilies
            ForEach(families, id: \.self) { family in
                Toggle(family, isOn: Binding(get: { family == format.attributes.fontFamily }, set: { _ in apply(.fontFamily(family)) }))
            }
        } label: {
            Text(format.attributes.fontFamily).lineLimit(1)
        }
        .fixedSize()
        .help("Font")
        .accessibilityLabel("Font")
        .accessibilityValue(format.attributes.fontFamily)
    }

    private var sizeMenu: some View {
        Menu {
            ForEach(Self.offeredSizes, id: \.self) { size in Button("\(Self.sizeText(size)) pt") { apply(.fontSize(size)) } }
        } label: {
            Text("\(Self.sizeText(format.attributes.fontSize)) pt").monospacedDigit()
        }
        .fixedSize()
        .help("Size")
        .accessibilityLabel("Size")
        .accessibilityValue("\(Self.sizeText(format.attributes.fontSize)) points")
    }

    /// Sizes offered, in points, as on the iPad.
    private static let offeredSizes: [Double] = [8, 10, 12, 14, 16, 18, 20, 24, 28, 32, 40, 48, 64, 72]

    private static func sizeText(_ size: Double) -> String {
        size.rounded() == size ? String(Int(size)) : size.formatted(.number.precision(.fractionLength(1)))
    }

    private var faceButtons: some View {
        HStack(spacing: PDFMarkupRowMetrics.itemSpacing) {
            faceToggle("Bold", systemImage: "bold", isOn: format.attributes.isBold) { apply(.bold(!format.attributes.isBold)) }
            faceToggle("Italic", systemImage: "italic", isOn: format.attributes.isItalic) { apply(.italic(!format.attributes.isItalic)) }
            faceToggle("Underline", systemImage: "underline", isOn: format.attributes.isUnderlined) { apply(.underline(!format.attributes.isUnderlined)) }
        }
    }

    private func faceToggle(_ title: String, systemImage: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: PDFMarkupRowMetrics.toolSide - 4, height: PDFMarkupRowMetrics.toolSide - 4)
                .background(PDFMarkupRowMetrics.chosenBackground(isOn))
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
    }

    private var colorMenu: some View {
        Menu {
            ForEach(PDFMarkupRowColors.choices(storedPalette: storedColorPalette), id: \.name) { choice in
                Button(choice.name) { apply(.color(choice.color)) }
            }
        } label: {
            Image(nsImage: PDFMarkupRowImages.swatch(format.attributes.color))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Text Color")
        .accessibilityLabel("Text Color")
    }

    private var alignmentPicker: some View {
        Picker("Alignment", selection: Binding(get: { format.boxStyle.alignment }, set: { alignment in apply(.alignment(alignment)) })) {
            ForEach(PDFTextAlignment.allCases, id: \.self) { alignment in
                Image(systemName: Self.symbolName(of: alignment)).accessibilityLabel(alignment.rawValue.capitalized).tag(alignment)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .help("Alignment")
    }

    private static func symbolName(of alignment: PDFTextAlignment) -> String {
        switch alignment {
        case .left: "text.alignleft"
        case .center: "text.aligncenter"
        case .right: "text.alignright"
        case .justified: "text.justify"
        }
    }

    /// Light fills that keep black text readable, as on the iPad.
    private static let offeredFills: [(name: String, color: PDFTextColor)] = [
        ("White", PDFTextColor(red: 1, green: 1, blue: 1)), ("Yellow", PDFTextColor(red: 1, green: 0.96, blue: 0.62)),
        ("Green", PDFTextColor(red: 0.83, green: 0.95, blue: 0.8)), ("Blue", PDFTextColor(red: 0.82, green: 0.9, blue: 1)),
        ("Pink", PDFTextColor(red: 1, green: 0.85, blue: 0.9)),
    ]

    @ViewBuilder private var fillItems: some View {
        Button("No Fill") { apply(.fill(nil)) }
        ForEach(Self.offeredFills, id: \.name) { fill in Button("\(fill.name) Fill") { apply(.fill(fill.color)) } }
    }

    private var fillMenu: some View {
        Menu { fillItems } label: {
            Image(systemName: format.boxStyle.fillColor == nil ? "square.dashed" : "square.fill")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Fill")
        .accessibilityLabel("Fill")
    }

    private var borderToggle: some View {
        faceToggle("Border", systemImage: "square", isOn: format.boxStyle.hasBorder) {
            apply(.border(width: format.boxStyle.hasBorder ? 0 : PDFTextBoxFormatChange.standardBorderWidth))
        }
    }

    /// Alignment, fill and border in one menu, for a narrow row.
    private var paragraphMenu: some View {
        Menu {
            Picker("Alignment", selection: Binding(get: { format.boxStyle.alignment }, set: { alignment in apply(.alignment(alignment)) })) {
                ForEach(PDFTextAlignment.allCases, id: \.self) { alignment in Text(alignment.rawValue.capitalized).tag(alignment) }
            }
            Section { fillItems }
            Toggle("Border", isOn: Binding(get: { format.boxStyle.hasBorder },
                                           set: { hasBorder in apply(.border(width: hasBorder ? PDFTextBoxFormatChange.standardBorderWidth : 0)) }))
        } label: {
            Image(systemName: "text.alignleft")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Alignment, Fill and Border")
        .accessibilityLabel("Box Format")
    }
}
#endif
