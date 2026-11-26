/**
 * File: PDFMarkMenus.swift
 * ------------------------
 * Layer: UI
 * Description: The iPad's menus for text marks: the Highlight, Underline and Strikethrough items of the text
 *              selection menu and the Color menu of a tapped mark, in the saved text-mark colours with Other Color…,
 *              and the system colour picker that item opens.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 17/11/2026
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
/// colour is then saved with the text-mark colours. As a popover the picker has no close
/// button and never reports finishing (`colorPickerViewControllerDidFinish` comes only from
/// that button), so it is closed by a tap outside it, which its presentation reports.
/// The "+" beside the text highlighter instead takes each colour as it is picked
/// (`pickedColorDidChange`), into the saved colours and the style at once. One picker is made
/// ahead (`prepare`) and kept, and shown without the popover's animation: the popover took 1 to
/// 1.5 s to show after the "+" on the physical iPad (2026-11-17).
@MainActor
final class PDFMarkColorPicker: NSObject, UIColorPickerViewControllerDelegate, UIAdaptivePresentationControllerDelegate {
    private let preferences: UserDefaults
    private var choose: ((PDFMarkupColor) -> Void)?
    private var pickedColor: PDFMarkupColor?
    /// Takes each colour picked while the picker is open, in place of `choose` when it closes.
    private var pickedColorDidChange: ((PDFMarkupColor) -> Void)?
    /// The colour this picking added to the saved colours, replaced by the next one picked.
    private var colorAddedWhilePicking: PDFMarkupColor?
    /// The picker made ahead and kept, presented again once it is closed.
    private var keptPicker: UIColorPickerViewController?

    init(preferences: UserDefaults) {
        self.preferences = preferences
    }

    /// Makes the picker and loads its view ahead of the first tap, once.
    func prepare() {
        guard keptPicker == nil else { return }
        let picker = UIColorPickerViewController()
        picker.supportsAlpha = false
        picker.delegate = self
        picker.loadViewIfNeeded()
        keptPicker = picker
    }

    /// Presents the picker with `color` from the view's window, pointing at `sourcePoint` of
    /// `view`, and calls `choose` once with the colour picked, if one was. With
    /// `pickedColorDidChange`, each colour picked is saved at once, replacing the one picked
    /// before it in this picking, and handed to it instead; `choose` is not called.
    func present(with color: PDFMarkupColor, from view: UIView, at sourcePoint: CGPoint,
                 pickedColorDidChange: ((PDFMarkupColor) -> Void)? = nil, choose: @escaping (PDFMarkupColor) -> Void) {
        guard var presenter = view.window?.rootViewController else { return }
        while let presented = presenter.presentedViewController { presenter = presented }
        prepare()
        guard let keptPicker else { return }
        // The kept picker shows once at a time; while it is shown, another is made.
        let picker = keptPicker.presentingViewController == nil ? keptPicker : UIColorPickerViewController()
        picker.supportsAlpha = false
        picker.delegate = self
        picker.selectedColor = color.platformColor
        picker.modalPresentationStyle = .popover
        picker.popoverPresentationController?.sourceView = view
        picker.popoverPresentationController?.sourceRect = CGRect(origin: sourcePoint, size: .zero)
        picker.presentationController?.delegate = self
        self.choose = choose
        self.pickedColorDidChange = pickedColorDidChange
        pickedColor = nil
        colorAddedWhilePicking = nil
        // Shown without the popover's animation: with it the picker was fully shown 0.62 to 0.69 s after the tap in an
        // iPad simulator (1 to 1.5 s on the physical iPad), without it 0.09 to 0.13 s.
        presenter.present(picker, animated: false)
    }

    func colorPickerViewController(_ viewController: UIColorPickerViewController, didSelect color: UIColor, continuously: Bool) {
        let picked = PDFMarkupColor(platformColor: color)
        pickedColor = picked
        // A colour dragged over in the spectrum or a slider is taken where the drag ends.
        guard !continuously, let pickedColorDidChange else { return }
        keepWhilePicking(picked)
        pickedColorDidChange(picked)
    }

    /// Saves `color` at once, in place of the colour this picking added before it: the earlier
    /// one removed, then this one added. A colour saved before the picking stays.
    private func keepWhilePicking(_ color: PDFMarkupColor) {
        let key = PDFAnnotationPreferenceKey.textMarkColors
        var saved = PDFTextMarkColors(decoding: preferences.data(forKey: key))
        let earlierColor = colorAddedWhilePicking
        if !saved.contains(color) {
            if let earlierColor { saved = saved.removing(earlierColor) }
            saved = saved.adding(color)
            colorAddedWhilePicking = color
        } else if earlierColor != color, let earlierColor {
            saved = saved.removing(earlierColor)
            colorAddedWhilePicking = nil
        }
        preferences.set(saved.encoded, forKey: key)
    }

    /// The close button, shown when the popover becomes a sheet in a compact width.
    func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) {
        finish()
    }

    /// A tap outside the popover, or a sheet swiped down.
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        finish()
    }

    /// Saves the colour picked and hands it back, once; with no colour picked, nothing. A
    /// picking that took each colour as it came is over: its colours are saved already.
    private func finish() {
        let chosenColor = pickedColor
        let chooseColor = choose
        let tookEachColor = pickedColorDidChange != nil
        pickedColor = nil
        choose = nil
        pickedColorDidChange = nil
        colorAddedWhilePicking = nil
        guard !tookEachColor, let chosenColor, let chooseColor else { return }
        PDFTextMarkColors.save(chosenColor, in: preferences)
        chooseColor(chosenColor)
    }
}
#endif
