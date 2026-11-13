/**
 * File: PencilColorPickerPresenter.swift
 * --------------------------------------
 * Layer: UI
 * Description: Opens the system color picker in a popover pointing at the Pencil bar's chosen color, as a second tap on
 *              it does in Apple's markup palette, and reports the colors picked in it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 13/11/2026
 */

#if canImport(UIKit)
import SwiftUI
import UIKit

/// Presents `UIColorPickerViewController` from the view the bar's row of colors puts behind itself
/// (`PencilColorPickerAnchor`), pointing at the chosen color's place in it. SwiftUI's `ColorPicker` opens only from
/// its own well, so a second tap on a color goes through UIKit. The bar keeps one presenter for its life; nothing is presented until `present` is called.
@MainActor
final class PencilColorPickerPresenter: NSObject, UIColorPickerViewControllerDelegate {
    /// The row's view, which the popover points into.
    fileprivate weak var anchorView: UIView?
    /// What the picker reports to: every color as it is picked, and whether picking it has ended.
    private var reportPickedColor: ((_ hex: String, _ isFinal: Bool) -> Void)?

    /// Whether the row's view is on screen, so a second tap can open the picker.
    var canPresent: Bool { anchorView?.window != nil }

    /// Opens the picker on `hex`, titled `title`, pointing at `sourceRect` of the row (the chosen color);
    /// `reportPickedColor` gets each color picked (`isFinal` false while a finger moves over the picker's spectrum,
    /// true when it lifts or the picker closes).
    func present(hex: String, title: String, sourceRect: CGRect, reportPickedColor: @escaping (_ hex: String, _ isFinal: Bool) -> Void) {
        guard let anchorView, let presenter = Self.topmostController(from: anchorView.window?.rootViewController) else { return }
        let picker = UIColorPickerViewController()
        picker.title = title
        picker.supportsAlpha = false
        picker.selectedColor = UIColor(Color(graphiteHex: hex) ?? .black)
        picker.delegate = self
        picker.modalPresentationStyle = .popover
        picker.popoverPresentationController?.sourceView = anchorView
        picker.popoverPresentationController?.sourceRect = sourceRect
        picker.popoverPresentationController?.permittedArrowDirections = [.up, .down]
        self.reportPickedColor = reportPickedColor
        presenter.present(picker, animated: true)
    }

    func colorPickerViewController(_ viewController: UIColorPickerViewController, didSelect color: UIColor, continuously: Bool) {
        guard let hex = Color(uiColor: color).sRGBHex else { return }
        reportPickedColor?(hex, !continuously)
    }

    func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) {
        if let hex = Color(uiColor: viewController.selectedColor).sRGBHex { reportPickedColor?(hex, true) }
        reportPickedColor = nil
    }

    private static func topmostController(from root: UIViewController?) -> UIViewController? {
        var controller = root
        while let presented = controller?.presentedViewController, !presented.isBeingDismissed { controller = presented }
        return controller
    }
}

/// The row's view for the presenter: an empty view as large as the row, behind it, which moves with it when it scrolls.
struct PencilColorPickerAnchor: UIViewRepresentable {
    let presenter: PencilColorPickerPresenter

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        presenter.anchorView = view
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {}
}
#endif
