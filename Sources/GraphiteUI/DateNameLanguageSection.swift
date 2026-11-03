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

import Foundation
import GraphiteCore
import Observation
import SwiftUI

/// The language of month and weekday names in dates written with Moment formats, for daily note names and template
/// dates. On this device, as Obsidian's Language is: it is not in the vault, and English keeps a vault's names as they are.
@MainActor
@Observable
final class DateNamePreferences {
    private enum Key {
        static let language = "GraphiteDateNameLanguage"
        static let earlierLanguages = "GraphiteEarlierDateNameLanguages"
    }

    private static let maximumEarlierLanguages = 4

    @ObservationIgnored private let defaults: UserDefaults
    /// The languages chosen before on this device, the last one first, whose notes are still read.
    @ObservationIgnored private var earlierLanguageCodes: [String]

    var language: MomentDateLanguage {
        didSet {
            guard language != oldValue else { return }
            defaults.set(language.id, forKey: Key.language)
            let otherEarlierCodes = earlierLanguageCodes.filter { code in code != oldValue.id && code != language.id }
            earlierLanguageCodes = Array(([oldValue.id] + otherEarlierCodes).prefix(Self.maximumEarlierLanguages))
            defaults.set(earlierLanguageCodes, forKey: Key.earlierLanguages)
            readingLanguages = Self.readingLanguages(chosen: language, earlierCodes: earlierLanguageCodes)
        }
    }

    /// The languages a daily note's name is read in: the chosen one first, then the earlier ones and English, so a note
    /// named before the choice changed is still found by date.
    private(set) var readingLanguages: [MomentDateLanguage]

    init(defaults: UserDefaults) {
        self.defaults = defaults
        let storedLanguage = MomentDateLanguage.named(defaults.string(forKey: Key.language))
        let storedEarlierCodes = defaults.stringArray(forKey: Key.earlierLanguages) ?? []
        language = storedLanguage
        earlierLanguageCodes = storedEarlierCodes
        readingLanguages = Self.readingLanguages(chosen: storedLanguage, earlierCodes: storedEarlierCodes)
    }

    private static func readingLanguages(chosen: MomentDateLanguage, earlierCodes: [String]) -> [MomentDateLanguage] {
        var languages = [chosen]
        for language in earlierCodes.map(MomentDateLanguage.named) + [.english] where !languages.contains(language) { languages.append(language) }
        return languages
    }
}

/// Obsidian writes daily note names in the language of the app on that device, which is not in the vault, so a vault
/// used with Obsidian in German needs this set to German for today's note to be the same file.
struct DateNameLanguageSection: View {
    private static let footer = "The language of month and weekday names in daily notes and template dates, on this device. "
        + "Choose the language Obsidian uses, which isn't stored in the vault, so today's note gets the name Obsidian gives it. "
        + "Notes named in an earlier language are still found. "
        + "Short names (MMM, ddd, dd) come from the system and can differ from Obsidian's."

    let preferences: DateNamePreferences

    var body: some View {
        Section {
            Picker("Language of Names", selection: Binding(get: { preferences.language.id }, set: { code in preferences.language = .named(code) })) {
                ForEach(MomentDateLanguage.choices) { choice in Text(choice.displayName).tag(choice.id) }
            }
        } footer: {
            Text(Self.footer)
                .formFooterAlignment()
        }
    }
}
