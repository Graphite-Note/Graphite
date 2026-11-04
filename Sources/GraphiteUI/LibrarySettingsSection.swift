/**
 * File: LibrarySettingsSection.swift
 * ----------------------------------
 * Layer: UI
 * Description: Settings > Appearance: how files are shown, as a library or as a list.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 01/11/2026
 */

import SwiftUI

/// Library or List, in Settings › Appearance; the same switch is where files are browsed.
struct LibrarySettingsSection: View {
    @Bindable var preferences: NotebookLibraryPreferences
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// What the section says. The switch beside the files is named only where it can be seen:
    /// a phone has it in the library's top row, so not while it lists files as a tree.
    static func explanation(presentation: LibraryPresentation, isCompactWidth: Bool) -> String {
        let choices = "Library shows folders and files as pictures of their pages; List shows Obsidian's file tree."
        if !isCompactWidth { return choices + " The switch beside your files changes it too." }
        return presentation == .library ? choices + " The switch at the top of the library changes it too." : choices
    }

    var body: some View {
        Section {
            Picker("Show Files As", selection: $preferences.presentation) {
                ForEach(LibraryPresentation.allCases) { presentation in Label(presentation.title, systemImage: presentation.systemImage).tag(presentation) }
            }
        } header: {
            Text("Files")
        } footer: {
            Text(Self.explanation(presentation: preferences.presentation, isCompactWidth: horizontalSizeClass == .compact))
                .formFooterAlignment()
        }
    }
}

/// The top of Settings › Appearance: the app's icon, where a phone or an iPad offers a
/// choice of icons, then how files are shown.
struct AppIconAndFilesSections: View {
    let library: NotebookLibraryPreferences

    var body: some View {
        #if os(iOS)
        AppIconSettingsSection()
        #endif
        LibrarySettingsSection(preferences: library)
    }
}
