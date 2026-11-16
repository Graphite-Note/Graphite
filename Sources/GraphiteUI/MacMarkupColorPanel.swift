/**
 * File: MacMarkupColorPanel.swift
 * -------------------------------
 * Layer: UI
 * Description: Opens the Mac's colour panel for a colour of the PDF markup row (a text mark's, the Draw tool's, a
 *              shape's or a text box's) and hands back the colour chosen, once per choice rather than while the
 *              pointer moves over the wheel.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

#if os(macOS)
import AppKit
import SwiftUI

/// The system colour panel for the colours of the markup row. The app has one colour panel
/// with one target, so it has one chooser: the last colour opened for receives the panel's
/// colours. The panel reports a colour only when the pointer lets go (`isContinuous` off):
/// one edit and one undo step per choice, not one per position of the wheel.
@MainActor
final class MacMarkupColorPanel: NSObject {
    /// The one chooser for the app's one panel (`NSColorPanel.shared`), which keeps no hold
    /// on its target: kept for the app's life, the target is never a released object.
    static let shared = MacMarkupColorPanel()

    private var choose: ((NSColor) -> Void)?

    private override init() { super.init() }

    /// Shows the panel with `color`, and calls `choose` with each colour picked in it until
    /// a colour is opened for again. `choose` should hold what it changes weakly, as the pane
    /// may close while the panel stays open.
    func open(with color: NSColor, choose: @escaping (NSColor) -> Void) {
        let panel = NSColorPanel.shared
        // The colour is set before the action is, so setting it reports nothing.
        self.choose = nil
        panel.isContinuous = false
        panel.showsAlpha = false
        panel.color = color
        panel.setTarget(self)
        panel.setAction(#selector(colorChosen(_:)))
        self.choose = choose
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func colorChosen(_ panel: NSColorPanel) {
        choose?(panel.color)
    }
}

/// The markup row's button that opens the colour panel, beside its swatches.
struct PDFMarkupColorPanelButton: View {
    let title: String
    let color: NSColor
    let choose: (NSColor) -> Void

    var body: some View {
        Button { MacMarkupColorPanel.shared.open(with: color, choose: choose) } label: {
            Image(systemName: "paintpalette")
                .frame(width: PDFMarkupRowMetrics.toolSide, height: PDFMarkupRowMetrics.toolSide)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(title)
        .accessibilityLabel(title)
    }
}
#endif
