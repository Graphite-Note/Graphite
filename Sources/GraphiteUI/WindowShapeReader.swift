/**
 * File: WindowShapeReader.swift
 * -----------------------------
 * Layer: UI
 * Description: Tells whether an iPad window is taller than wide, from the window's own bounds, which the software
 *              keyboard does not change.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 13/11/2026
 */

#if os(iOS)
import SwiftUI
import UIKit

/// Reports the shape of the window it is in: true when taller than wide. The root view measured its own size, which the
/// software keyboard takes its room from: an upright 11-inch iPad window, 834 by 1,194 points, is 834 by 822 above the
/// keyboard, wider than tall, so a tap in a note read as the iPad turning sideways and showed the sidebar beside the note
/// (HUNT-353). The window's bounds change only when the window does.
struct WindowShapeReader: UIViewRepresentable {
    let shapeMeasured: (Bool) -> Void

    func makeUIView(context: Context) -> WindowShapeReportingView {
        let view = WindowShapeReportingView()
        view.isUserInteractionEnabled = false
        view.shapeMeasured = shapeMeasured
        return view
    }

    func updateUIView(_ view: WindowShapeReportingView, context: Context) {
        view.shapeMeasured = shapeMeasured
    }
}

/// Lays out with the root view, so it hears of every change of the window's size, and reports a change of shape.
final class WindowShapeReportingView: UIView {
    var shapeMeasured: ((Bool) -> Void)?
    private var reportedShape: Bool?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        reportShapeIfChanged()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        reportShapeIfChanged()
    }

    private func reportShapeIfChanged() {
        // A window without its size yet measures nothing (HUNT-317).
        guard let window, window.bounds.width > 0, window.bounds.height > 0 else { return }
        let isTallerThanWide = window.bounds.height > window.bounds.width
        guard isTallerThanWide != reportedShape else { return }
        reportedShape = isTallerThanWide
        // After this layout pass: the root view's state changed from inside it would update SwiftUI within its own layout.
        DispatchQueue.main.async { [weak self] in self?.shapeMeasured?(isTallerThanWide) }
    }
}
#endif
