/**
 * File: SettingsDevice.swift
 * --------------------------
 * Layer: UI
 * Description: The kind of device Settings is written for: the Mac, an iPad, or a phone, which has neither Apple Pencil
 *              nor a keyboard to speak of.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 04/11/2026
 */

#if canImport(UIKit)
import UIKit
#endif

/// What Settings offers and says differs by device, not by window width: an iPad in a narrow window still has its
/// Pencil and its keyboard, and a phone has neither (HUNT-248, HUNT-255). One value, so the choice can be tested.
enum SettingsDevice {
    case mac, pad, phone

    /// On the main actor, as `UIDevice` is; Settings asks from its views.
    @MainActor static var current: SettingsDevice {
        #if os(macOS)
        .mac
        #else
        UIDevice.current.userInterfaceIdiom == .phone ? .phone : .pad
        #endif
    }

    /// Apple Pencil writes on an iPad only, so the Pencil's own options are the iPad's.
    var writesWithApplePencil: Bool { self == .pad }

    /// What Settings › Appearance says about changing the note's size quickly: a phone is not told about keys.
    var quickFontSizeAdjustmentSummary: String {
        switch self {
        case .mac: "Control-scroll or pinch on the trackpad over a note, or press ⌘+, ⌘– and ⌘0."
        case .pad: "Pinch a note with two fingers, or press ⌘+, ⌘– and ⌘0 on a keyboard."
        case .phone: "Pinch a note with two fingers."
        }
    }
}
