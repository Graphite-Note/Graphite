/**
 * File: DocumentTitle.swift
 * -------------------------
 * Layer: UI
 * Description: The document's name in the navigation bar: a plain title in a compact width, the editable title with
 *              its Rename menu elsewhere.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 13/11/2026
 */

import SwiftUI

/// The document's name in the navigation bar. A compact width shows it as a plain title,
/// which truncates to make room for the document's controls; the editable title, with its
/// Rename menu, kept its full width beside a long file name and sent Write, Undo and More
/// into an overflow menu. Rename is in the document's More menu there.
struct DocumentTitle: ViewModifier {
    @Binding var title: String
    let isCompactWidth: Bool

    func body(content: Content) -> some View {
        if isCompactWidth {
            content.navigationTitle(title)
        } else {
            content.navigationTitle($title)
        }
    }
}
