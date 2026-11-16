/**
 * File: PDFTextHighlighterStyleChoices.swift
 * ------------------------------------------
 * Layer: UI
 * Description: The iPad text highlighter's styles beside it on the Pencil bar: a dot per saved text-mark colour, a
 *              "+" that adds one from the colour picker, Underline and Strikethrough, the one in use ringed, kept on the
 *              device.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

import SwiftUI
import GraphiteApple

#if canImport(UIKit)
/// The text highlighter's styles beside it on the bar (`PencilToolChoices`): a dot per saved text-mark colour
/// (`PDFTextMarkColors`, shared with the Mac's markup row and both platforms' mark menus), a "+" that opens the system
/// colour picker and saves the colour picked as one more dot, then Underline and Strikethrough (`PDFMarkupStyle.choices`).
/// A long press on a dot offers to remove that colour. The style in use is ringed or stands on the bar's faint fill, so
/// it is told apart by shape as well as colour. The style is kept on the device under the key the Mac's highlight button
/// uses, read by the PDF view as `PDFAnnotationInput.markupStyle`.
struct PDFTextHighlighterStyleChoices: View {
    @AppStorage(PDFAnnotationPreferenceKey.markupStyle) private var style = PDFMarkupStyle.default
    @AppStorage(PDFAnnotationPreferenceKey.textMarkColors) private var storedColors: Data?
    /// The picker the "+" opens; it saves the colour picked with the text-mark colours.
    @State private var colorPicker = PDFMarkColorPicker(preferences: .standard)
    @State private var pickerAnchor = PDFTextMarkColorPickerAnchor.Holder()

    /// Each style's button: as wide as a color of the bar at its tight density, touched over the bar's height.
    private static let buttonWidth: CGFloat = 28
    private static let swatchDiameter: CGFloat = 20

    var body: some View {
        let savedColors = PDFTextMarkColors(decoding: storedColors)
        let choices = PDFMarkupStyle.choices(highlightColors: savedColors.colors)
        HStack(spacing: 0) {
            ForEach(choices.filter { choice in choice.kind == .highlight }, id: \.rawValue) { choice in
                button(for: choice)
                    .contextMenu {
                        Button("Remove Color", systemImage: "minus.circle", role: .destructive) {
                            storedColors = savedColors.removing(choice.color).encoded
                        }
                    }
            }
            addColorButton
            ForEach(choices.filter { choice in choice.kind != .highlight }, id: \.rawValue) { choice in button(for: choice) }
        }
        .fixedSize()
    }

    /// Opens the system colour picker on the colour in use; the colour picked is saved as a dot and becomes the style.
    private var addColorButton: some View {
        Button {
            guard let anchorView = pickerAnchor.view else { return }
            let startColor = style.kind == .highlight ? style.color : PDFMarkupStyle.default.color
            colorPicker.present(with: startColor, from: anchorView, at: CGPoint(x: anchorView.bounds.midX, y: anchorView.bounds.maxY)) { chosen in
                style = .highlight(chosen)
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: Self.buttonWidth, height: PencilToolbarMetrics.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background { PDFTextMarkColorPickerAnchor(holder: pickerAnchor) }
        .accessibilityLabel("Add Highlight Color")
    }

    private func button(for choice: PDFMarkupStyle) -> some View {
        let isInUse = style == choice
        return Button {
            style = choice
        } label: {
            label(for: choice, isInUse: isInUse)
                .frame(width: Self.buttonWidth, height: PencilToolbarMetrics.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(choice.kind == .highlight ? "Highlight \(choice.title)" : choice.title)
        .accessibilityAddTraits(isInUse ? .isSelected : [])
    }

    @ViewBuilder private func label(for choice: PDFMarkupStyle, isInUse: Bool) -> some View {
        switch choice.kind {
        case .highlight:
            Circle()
                .fill(Color(uiColor: choice.color.platformColor))
                .overlay { Circle().strokeBorder(Color.primary.opacity(0.6), lineWidth: 1) }
                .frame(width: Self.swatchDiameter, height: Self.swatchDiameter)
                .overlay {
                    if isInUse {
                        Circle().strokeBorder(.primary, lineWidth: 2).frame(width: Self.swatchDiameter + 6, height: Self.swatchDiameter + 6)
                    }
                }
        case .underline, .strikeOut:
            Image(systemName: choice.symbolName)
                .font(.system(size: 16, weight: isInUse ? .semibold : .regular))
                .foregroundStyle(Color(uiColor: choice.color.platformColor))
                .frame(width: Self.buttonWidth - 2, height: Self.buttonWidth - 2)
                .background(isInUse ? PencilToolbarMetrics.selectedFill : AnyShapeStyle(.clear),
                            in: RoundedRectangle(cornerRadius: GraphiteChrome.cornerRadius, style: .continuous))
        }
    }
}

/// The view behind the "+" that the colour picker's popover points at: SwiftUI's own `ColorPicker` opens only from its
/// well and reports every colour as the finger moves, where the picker here hands back one colour when it closes.
struct PDFTextMarkColorPickerAnchor: UIViewRepresentable {
    /// Holds the anchor's view weakly for the "+" that presents from it.
    @MainActor final class Holder {
        weak var view: UIView?
    }

    let holder: Holder

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        holder.view = view
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {}
}
#endif
