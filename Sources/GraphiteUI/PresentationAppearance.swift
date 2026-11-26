/**
 * File: PresentationAppearance.swift
 * ----------------------------------
 * Layer: UI
 * Description: The look a presented note's slides take wherever they are drawn, read from the window that started
 *              the presentation: the vault's theme and fonts, the code theme, the accent and light or dark.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import SwiftUI

/// The window's look, taken when a presentation starts, for the screens outside that window: an external
/// display's window and the Mac's presentation windows, which do not inherit the window's environment.
struct PresentationAppearance {
    let noteTheme: NoteThemeStyle?
    let typography: NoteTypography
    let codeColorTheme: CodeColorTheme
    let accent: Color
    /// Light or dark, as the app shows now (decision 4).
    let colorScheme: ColorScheme

    /// The look of a window whose notes take `noteTheme` and `typography`, with the code theme and accent of `preferences`.
    @MainActor
    init(noteTheme: NoteThemeStyle?, typography: NoteTypography, preferences: GraphitePreferences, colorScheme: ColorScheme) {
        self.init(noteTheme: noteTheme, typography: typography, codeColorTheme: preferences.codeColorTheme, accent: preferences.accentColor,
                  colorScheme: colorScheme)
    }

    init(noteTheme: NoteThemeStyle?, typography: NoteTypography, codeColorTheme: CodeColorTheme, accent: Color, colorScheme: ColorScheme) {
        self.noteTheme = noteTheme
        self.typography = typography
        self.codeColorTheme = codeColorTheme
        self.accent = accent
        self.colorScheme = colorScheme
    }

    #if canImport(UIKit)
    var userInterfaceStyle: UIUserInterfaceStyle { colorScheme == .dark ? .dark : .light }
    #endif
}

extension View {
    /// The environment a slide is drawn in outside the window that started the presentation.
    func presentationEnvironment(_ appearance: PresentationAppearance) -> some View {
        self
            .environment(\.noteTheme, appearance.noteTheme)
            .environment(\.noteTypography, appearance.typography)
            .environment(\.codeColorTheme, appearance.codeColorTheme)
            .environment(\.accent, appearance.accent)
            .environment(\.colorScheme, appearance.colorScheme)
            .tint(appearance.accent)
    }
}
