/**
 * File: Pasteboard.swift
 * ----------------------
 * Layer: UI
 * Description: Plain text on the system pasteboard.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.1
 * Date: 02/11/2026
 */

#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Plain text on the system pasteboard.
enum Pasteboard {
    static func copy(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    /// The text on the pasteboard, if any. On iPad and iPhone, iOS tells the person that
    /// Graphite read it.
    static var text: String? {
        #if canImport(UIKit)
        UIPasteboard.general.string
        #else
        NSPasteboard.general.string(forType: .string)
        #endif
    }
}
