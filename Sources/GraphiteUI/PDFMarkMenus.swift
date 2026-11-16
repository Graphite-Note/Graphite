/**
 * File: PDFMarkMenus.swift
 * ------------------------
 * Layer: UI
 * Description: The iPad's menus for text marks: the Highlight, Underline and Strikethrough items of the text
 *              selection menu and the Color menu of a tapped mark, in the saved text-mark colours with Other Color…,
 *              and the system colour picker that item opens.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

#if canImport(UIKit)
import UIKit
import GraphiteApple

/// The iPad's menus for text marks, in the colours saved on the device (`PDFTextMarkColors`).
@MainActor
enum PDFMarkMenus {
    /// Highlight (a submenu of the colours, Other Color… and Remove a Color), then Underline
    /// and Strikethrough, each red, for the text selection menu. `mark` marks the selected text.
    static func markingItems(savedColors: PDFTextMarkColors, mark: @escaping (PDFMarkupStyle) -> Void,
                             pickColor: @escaping (PDFMarkupColor, @escaping (PDFMarkupColor) -> Void) -> Void,
                             removeSavedColor: @escaping (PDFMarkupColor) -> Void) -> [UIMenuElement] {
        let colorActions = savedColors.colors.map { color in
            UIAction(title: color.title, image: swatch(for: color)) { _ in mark(.highlight(color)) }
        }
        let otherColor = UIAction(title: "Other Color…", image: UIImage(systemName: "paintpalette")) { _ in
            pickColor(savedColors.colors.first ?? .yellow) { chosen in mark(.highlight(chosen)) }
        }
        let removeActions = savedColors.colors.map { color in
            UIAction(title: color.title, image: swatch(for: color), attributes: .destructive) { _ in removeSavedColor(color) }
        }
        var highlightChildren: [UIMenuElement] = colorActions + [otherColor]
        if !removeActions.isEmpty {
            highlightChildren.append(UIMenu(title: "Remove a Color", image: UIImage(systemName: "minus.circle"), children: removeActions))
        }
        let highlight = UIMenu(title: PDFMarkupKind.highlight.title, image: UIImage(systemName: "highlighter"), children: highlightChildren)
        let underline = UIAction(title: PDFMarkupKind.underline.title, image: UIImage(systemName: "underline")) { _ in mark(.underline) }
        let strikeOut = UIAction(title: PDFMarkupKind.strikeOut.title, image: UIImage(systemName: "strikethrough")) { _ in mark(.strikeOut) }
        return [highlight, underline, strikeOut]
    }

    /// The Color menu of a tapped mark: the colours for its kind with its own colour first
    /// when it is none of them (another application's), ticked, then Other Color….
    static func colorMenu(for kind: PDFMarkupKind, currentColor: PDFMarkupColor?, savedColors: PDFTextMarkColors,
                          recolor: @escaping (PDFMarkupColor) -> Void,
                          pickColor: @escaping (PDFMarkupColor, @escaping (PDFMarkupColor) -> Void) -> Void) -> UIMenu {
        let colorActions: [UIMenuElement] = savedColors.offered(for: kind, including: currentColor).map { color in
            UIAction(title: color.title, image: swatch(for: color), state: color == currentColor ? .on : .off) { _ in recolor(color) }
        }
        let otherColor = UIAction(title: "Other Color…", image: UIImage(systemName: "paintpalette")) { _ in
            pickColor(currentColor ?? .yellow, recolor)
        }
        return UIMenu(title: "Color", image: UIImage(systemName: "paintpalette"), children: colorActions + [otherColor])
    }

    static func swatch(for color: PDFMarkupColor) -> UIImage? {
        UIImage(systemName: "circle.fill")?.withTintColor(color.platformColor, renderingMode: .alwaysOriginal)
    }
}

/// The system colour picker for a text mark's colour, presented over the PDF. It hands
/// back one colour, when the picker is closed, so a mark changes once, as one step; the
/// colour is then saved with the text-mark colours.
@MainActor
final class PDFMarkColorPicker: NSObject, UIColorPickerViewControllerDelegate {
    private let preferences: UserDefaults
    private var choose: ((PDFMarkupColor) -> Void)?
    private var pickedColor: PDFMarkupColor?

    init(preferences: UserDefaults) {
        self.preferences = preferences
    }

    /// Presents the picker with `color` from the view's window, pointing at `sourcePoint` of
    /// `view`, and calls `choose` once with the colour picked, if one was.
    func present(with color: PDFMarkupColor, from view: UIView, at sourcePoint: CGPoint, choose: @escaping (PDFMarkupColor) -> Void) {
        guard var presenter = view.window?.rootViewController else { return }
        while let presented = presenter.presentedViewController { presenter = presented }
        let picker = UIColorPickerViewController()
        picker.selectedColor = color.platformColor
        picker.supportsAlpha = false
        picker.delegate = self
        picker.modalPresentationStyle = .popover
        picker.popoverPresentationController?.sourceView = view
        picker.popoverPresentationController?.sourceRect = CGRect(origin: sourcePoint, size: .zero)
        self.choose = choose
        pickedColor = nil
        presenter.present(picker, animated: true)
    }

    func colorPickerViewController(_ viewController: UIColorPickerViewController, didSelect color: UIColor, continuously: Bool) {
        pickedColor = PDFMarkupColor(platformColor: color)
    }

    func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) {
        defer { choose = nil }
        guard let pickedColor, let choose else { return }
        PDFTextMarkColors.save(pickedColor, in: preferences)
        choose(pickedColor)
    }
}
#endif
