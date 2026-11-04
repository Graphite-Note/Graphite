/**
 * File: PencilBarMoreButton.swift
 * -------------------------------
 * Layer: UI
 * Description: The one control at the end of a narrow Pencil bar that opens, in a popover, what the bar has no room
 *              for.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 04/11/2026
 */

import SwiftUI

#if canImport(UIKit)
/// The control at the end of the compact and the condensed Pencil bar, which opens `content` in a popover: Apple's own
/// way when a bar has no room for its controls. It is touched over the row's whole height and its own width; `label`
/// is told whether the popover is open, to show it on the control.
struct PencilBarMoreButton<Label: View, Content: View>: View {
    let accessibilityLabel: String
    var accessibilityValue = ""
    let width: Double
    let rowHeight: CGFloat
    @ViewBuilder var label: (_ isPresented: Bool) -> Label
    @ViewBuilder var content: Content
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            label(isPresented)
                .frame(width: width, height: rowHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .popover(isPresented: $isPresented) {
            VStack(alignment: .leading, spacing: 4) { content }
                .padding(12)
                .tint(.primary)
                .presentationCompactAdaptation(.popover)
        }
    }
}
#endif
