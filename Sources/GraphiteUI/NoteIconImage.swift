/**
 * File: NoteIconImage.swift
 * -------------------------
 * Layer: UI
 * Description: A note's icon drawn beside its name: an emoji as text, an SF Symbol in the secondary color, nothing for
 *              a symbol name the system does not have.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import SwiftUI
import GraphiteCore
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// A note's icon at a given size. Decorative: the note's name beside it is what VoiceOver reads.
struct NoteIconImage: View {
    let icon: NoteIcon
    let pointSize: CGFloat

    var body: some View {
        Group {
            switch icon {
            case .emoji(let emoji):
                Text(verbatim: emoji).font(.system(size: pointSize))
            case .symbol(let systemName):
                if NoteIconImage.systemHasSymbol(named: systemName) {
                    Image(systemName: systemName).font(.system(size: pointSize)).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// Whether the system draws a symbol of this name: a name written by hand may name none.
    static func systemHasSymbol(named systemName: String) -> Bool {
        #if canImport(UIKit)
        UIImage(systemName: systemName) != nil
        #else
        NSImage(systemSymbolName: systemName, accessibilityDescription: nil) != nil
        #endif
    }
}
