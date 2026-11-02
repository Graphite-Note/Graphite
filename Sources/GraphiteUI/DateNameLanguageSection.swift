/**
 * File: DateNameLanguageSection.swift
 * -----------------------------------
 * Layer: UI
 * Description: The Daily Notes settings' choice of the language month and weekday names are written and read in.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 02/11/2026
 */

import GraphiteCore
import SwiftUI

/// Obsidian writes daily note names in the language of the app on that device, which is not in the vault, so a vault
/// used with Obsidian in German needs this set to German for today's note to be the same file.
struct DateNameLanguageSection: View {
    let preferences: GraphitePreferences

    var body: some View {
        Section {
            Picker("Language of Names", selection: Binding(get: { preferences.dateNameLanguage.id }, set: { code in preferences.dateNameLanguage = .named(code) })) {
                ForEach(MomentDateLanguage.choices) { choice in Text(choice.displayName).tag(choice.id) }
            }
        } footer: {
            Text("The language of month and weekday names in daily notes and template dates, on this device. Choose the language Obsidian uses, which isn't stored in the vault, so today's note gets the name Obsidian gives it. Notes named in an earlier language are still found. Short names (MMM, ddd, dd) come from the system and can differ from Obsidian's.")
                .formFooterAlignment()
        }
    }
}
