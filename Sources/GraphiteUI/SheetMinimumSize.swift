/**
 * File: SheetMinimumSize.swift
 * ----------------------------
 * Layer: UI
 * Description: The one way a sheet asks for a minimum size: on the Mac only, where a sheet fits its content, and never
 *              on an iPhone, in Slide Over or in a narrow split, where it takes the width it is given.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import SwiftUI

extension View {
    /// Gives a sheet the least size it is laid out at on the Mac. An iOS sheet is 375 to 440 points wide on a phone
    /// and as narrow in Slide Over, and a minimum of 340 to 520 points pushed its Cancel and title bar off the screen
    /// (HUNT-271, HUNT-272); the iPad's form sheet and a phone's page sheet size themselves.
    func sheetMinimumSize(width: CGFloat, height: CGFloat) -> some View {
        #if os(macOS)
        frame(minWidth: width, minHeight: height)
        #else
        self
        #endif
    }
}
