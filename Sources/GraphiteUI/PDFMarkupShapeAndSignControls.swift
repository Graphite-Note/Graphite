/**
 * File: PDFMarkupShapeAndSignControls.swift
 * -----------------------------------------
 * Layer: UI
 * Description: The Mac markup row's Shapes choices (rectangle, oval, line, arrow, border colour, fill and width, laid
 *              out or folded into menus) and its Sign menu of the device's signatures, with Create Signature.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 13/11/2026
 */

#if os(macOS)
import SwiftUI
import AppKit
import PencilKit
import GraphiteCore
import GraphiteApple

extension PDFShapeKind {
    var symbolName: String {
        switch self {
        case .rectangle: "rectangle"
        case .oval: "oval"
        case .line: "line.diagonal"
        case .arrow: "arrow.up.right"
        }
    }
}

/// The Shapes tool's choices: the four shapes, then the border colours, the fills and the
/// line widths, as buttons in a wide row and one menu each in a narrow one. A choice is for
/// the selected shape and the next one (`PDFMarkupToolbar.chooseShapeStyle`).
struct PDFMarkupShapeOptions: View {
    let toolbar: PDFMarkupToolbar
    @Binding var shapeStyle: PDFMarkupShapeStyle
    let isFolded: Bool
    @AppStorage(GraphitePreferences.colorPaletteKey) private var storedColorPalette: Data?

    private var colors: [(name: String, color: PDFTextColor)] { PDFMarkupRowColors.choices(storedPalette: storedColorPalette) }

    private func choose(_ change: (inout PDFMarkupShapeStyle) -> Void) {
        var changed = toolbar.shapeStyle
        change(&changed)
        shapeStyle = changed
        toolbar.chooseShapeStyle(changed)
    }

    var body: some View {
        let style = toolbar.shapeStyle
        HStack(spacing: PDFMarkupRowMetrics.itemSpacing) {
            if isFolded {
                kindMenu(style)
                borderMenu(style)
                fillMenu(style)
                widthMenu(style)
            } else {
                ForEach(PDFShapeKind.allCases) { kind in kindButton(kind, isInUse: style.kind == kind) }
                divider
                ForEach(colors, id: \.name) { choice in
                    colorButton(label: "Border \(choice.name)", color: choice.color, isInUse: style.borderColor == choice.color) { changed in
                        changed.borderColor = choice.color
                    }
                }
                divider
                noFillButton(isInUse: style.fillColor == nil)
                ForEach(colors, id: \.name) { choice in
                    colorButton(label: "Fill \(choice.name)", color: choice.color, isInUse: style.fillColor == choice.color, isFill: true) { changed in
                        changed.fillColor = choice.color
                    }
                }
                divider
                ForEach(PDFMarkupInkWidth.allCases) { width in widthButton(width, isInUse: style.width == width) }
            }
        }
    }

    private var divider: some View {
        Divider().frame(height: PDFMarkupRowMetrics.dividerHeight).padding(.horizontal, 4)
    }

    private func kindButton(_ kind: PDFShapeKind, isInUse: Bool) -> some View {
        Button { choose { changed in changed.kind = kind } } label: {
            Image(systemName: kind.symbolName)
                .frame(width: PDFMarkupRowMetrics.toolSide, height: PDFMarkupRowMetrics.toolSide)
                .background(PDFMarkupRowMetrics.chosenBackground(isInUse))
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(kind.title)
        .accessibilityLabel(kind.title)
        .accessibilityAddTraits(isInUse ? .isSelected : [])
    }

    private func colorButton(label: String, color: PDFTextColor, isInUse: Bool, isFill: Bool = false,
                             change: @escaping (inout PDFMarkupShapeStyle) -> Void) -> some View {
        Button { choose(change) } label: {
            if isFill {
                PDFMarkupSwatch(color: Color(textColor: color), isInUse: isInUse)
            } else {
                PDFMarkupRingSwatch(color: Color(textColor: color), isInUse: isInUse)
            }
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isInUse ? .isSelected : [])
    }

    private func noFillButton(isInUse: Bool) -> some View {
        Button { choose { changed in changed.fillColor = nil } } label: {
            Image(systemName: "circle.slash")
                .frame(width: PDFMarkupRowMetrics.toolSide - 4, height: PDFMarkupRowMetrics.toolSide)
                .background(PDFMarkupRowMetrics.chosenBackground(isInUse))
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help("No Fill")
        .accessibilityLabel("No Fill")
        .accessibilityAddTraits(isInUse ? .isSelected : [])
    }

    private func widthButton(_ width: PDFMarkupInkWidth, isInUse: Bool) -> some View {
        Button { choose { changed in changed.width = width } } label: {
            Capsule().fill(Color.primary).frame(width: 14, height: max(1, CGFloat(width.points)))
                .frame(width: PDFMarkupRowMetrics.toolSide, height: PDFMarkupRowMetrics.toolSide)
                .background(PDFMarkupRowMetrics.chosenBackground(isInUse))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(width.title) Border")
        .accessibilityLabel("\(width.title) Border")
        .accessibilityAddTraits(isInUse ? .isSelected : [])
    }

    private func kindMenu(_ style: PDFMarkupShapeStyle) -> some View {
        Menu {
            ForEach(PDFShapeKind.allCases) { kind in
                Button(kind.title, systemImage: kind.symbolName) { choose { changed in changed.kind = kind } }
            }
        } label: {
            Image(systemName: style.kind.symbolName)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("Shape")
    }

    private func borderMenu(_ style: PDFMarkupShapeStyle) -> some View {
        Menu {
            ForEach(colors, id: \.name) { choice in
                Button(choice.name) { choose { changed in changed.borderColor = choice.color } }
            }
        } label: {
            Image(nsImage: PDFMarkupRowImages.swatch(style.borderColor))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Border Color")
        .accessibilityLabel("Border Color")
    }

    private func fillMenu(_ style: PDFMarkupShapeStyle) -> some View {
        Menu {
            Button("No Fill") { choose { changed in changed.fillColor = nil } }
            ForEach(colors, id: \.name) { choice in
                Button(choice.name) { choose { changed in changed.fillColor = choice.color } }
            }
        } label: {
            if let fill = style.fillColor {
                Image(nsImage: PDFMarkupRowImages.swatch(fill))
            } else {
                Image(systemName: "circle.slash")
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Fill Color")
        .accessibilityLabel("Fill Color")
    }

    private func widthMenu(_ style: PDFMarkupShapeStyle) -> some View {
        Menu {
            ForEach(PDFMarkupInkWidth.allCases) { width in Button("\(width.title) Border") { choose { changed in changed.width = width } } }
        } label: {
            Image(nsImage: PDFMarkupRowImages.line(style.width))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("Border Width")
    }
}

/// A border colour's swatch: a ring of the colour, ringed again while it is the one in use.
struct PDFMarkupRingSwatch: View {
    let color: Color
    let isInUse: Bool

    var body: some View {
        Circle().strokeBorder(color, lineWidth: 3)
            .frame(width: PDFMarkupRowMetrics.swatchSide, height: PDFMarkupRowMetrics.swatchSide)
            .overlay {
                if isInUse {
                    Circle().strokeBorder(Color.primary, lineWidth: 1.5)
                        .frame(width: PDFMarkupRowMetrics.chosenRingSide, height: PDFMarkupRowMetrics.chosenRingSide)
                }
            }
            .frame(width: PDFMarkupRowMetrics.toolSide - 4, height: PDFMarkupRowMetrics.toolSide)
            .contentShape(Rectangle())
    }
}

/// The Sign menu of the row: the signatures kept on this Mac, each placed on the page in
/// view when chosen, Create Signature, which opens the sheet to draw one, and a submenu to
/// delete them. Shown only where the device can keep signatures.
struct PDFMarkupSignMenu: View {
    let toolbar: PDFMarkupToolbar
    let store: PDFSignatureStore
    /// Shows why a signature could not be deleted, in the PDF's banner.
    let reportFailure: (Error) -> Void

    /// The height of a signature's picture in the menu, in points.
    private static let pictureHeight: CGFloat = 28
    private static let pictureWidestWidth: CGFloat = 140

    var body: some View {
        Menu {
            ForEach(Array(store.signatures.enumerated()), id: \.element.id) { position, signature in
                Button { toolbar.placeSignature(signature) } label: {
                    Label { Text("Signature \(position + 1)") } icon: { Image(nsImage: Self.picture(of: signature)) }
                }
            }
            if !store.signatures.isEmpty { Divider() }
            Button("Create Signature…") { toolbar.isCreatingSignature = true }
            if !store.signatures.isEmpty {
                Menu("Delete Signature") {
                    ForEach(Array(store.signatures.enumerated()), id: \.element.id) { position, signature in
                        Button { deleteSignature(signature) } label: {
                            Label { Text("Signature \(position + 1)") } icon: { Image(nsImage: Self.picture(of: signature)) }
                        }
                    }
                }
            }
        } label: {
            Image(systemName: PDFMarkupTool.sign.symbolName)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
        .fixedSize()
        .padding(.horizontal, 2)
        .background(PDFMarkupRowMetrics.chosenBackground(toolbar.tool == .sign))
        .help("Sign")
        .accessibilityLabel("Sign")
        .onAppear { store.loadIfNeeded() }
    }

    private func deleteSignature(_ signature: PDFSavedSignature) {
        do { try store.delete(signature) } catch { reportFailure(error) }
    }

    /// The signature drawn in the label colour, so it shows on a light and a dark menu.
    static func picture(of signature: PDFSavedSignature) -> NSImage {
        let bounds = signature.drawing.bounds
        guard bounds.width > 0, bounds.height > 0 else { return NSImage() }
        let scale = min(pictureHeight / bounds.height, pictureWidestWidth / bounds.width)
        let size = NSSize(width: bounds.width * scale, height: bounds.height * scale)
        let strokes = signature.drawing.image(from: bounds, scale: 2)
        return NSImage(size: size, flipped: false) { rectangle in
            NSColor.labelColor.setFill()
            rectangle.fill()
            strokes.draw(in: rectangle, from: .zero, operation: .destinationIn, fraction: 1)
            return true
        }
    }
}
#endif
