/**
 * File: MomentDateLanguage.swift
 * ------------------------------
 * Layer: Core
 * Description: The language of the month and weekday names in dates written with Moment formats, as Obsidian's
 *              Language setting chooses them on a device.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 02/11/2026
 */

import Foundation

/// A language for the names in Moment dates. Obsidian formats dates with Moment in the app's language, which it keeps
/// per device, so the same format names a different file in another language.
///
/// Abbreviated names (`MMM`, `ddd`, `dd`) are Foundation's. They differ from Moment's in many languages, such as `Sept.`
/// where Moment has `Sep.` in German; `MomentDateReader` reads both forms, so a note Obsidian wrote is still found.
/// Full names (`MMMM`, `dddd`), `Do` and digits match Moment's: `MomentDateLanguageDefinition.all` holds Moment's own
/// where Foundation's differ. Long formats (`LL`), `A` and era names stay English.
public struct MomentDateLanguage: Sendable, Identifiable, Equatable {
    /// Obsidian's code for the language, as in its Language setting.
    public let id: String
    let months: [String]
    /// The months after a day in the same format, where a language inflects them (`1 ноября`, against `ноябрь`).
    let monthsAfterDay: [String]
    let abbreviatedMonths: [String]
    let weekdays: [String]
    let abbreviatedWeekdays: [String]
    let shortestWeekdays: [String]
    /// The forms read beside the written ones: nothing here is written.
    let otherMonthForms: [[String]]
    let otherAbbreviatedMonthForms: [[String]]
    let otherWeekdayForms: [[String]]
    let otherAbbreviatedWeekdayForms: [[String]]
    let firstWeekday: Int
    let minimumDaysInFirstWeek: Int
    /// Polish's Moment takes the form after a day only right after `D MMMM`, where the others allow more.
    let takesMonthAfterDayOnlyRightAfterIt: Bool
    private let ordinalTemplate: String
    private let ordinalExceptions: [Int: String]
    private let digits: [Character]
    private let comma: Character?
    private let ordinalsAreEnglish: Bool

    public static func == (first: MomentDateLanguage, second: MomentDateLanguage) -> Bool { first.id == second.id }

    /// Moment's default locale, which is what Obsidian writes in English.
    public static let english = MomentDateLanguage(english: ())

    /// The language with Obsidian's code `code`; English for a code that is not offered.
    public static func named(_ code: String?) -> MomentDateLanguage {
        guard let definition = MomentDateLanguageDefinition.all.first(where: { definition in definition.code == code }) else { return .english }
        return MomentDateLanguage(definition)
    }

    /// A language to choose from, without its names, which take a moment to read from the system.
    public struct Choice: Sendable, Identifiable, Equatable {
        public let id: String
        /// The language's name in itself: `Deutsch`.
        public let displayName: String
    }

    /// English, then Obsidian's languages Foundation has names for, by name. Left out on purpose: English (GB), named as
    /// English, and Amharic, Kabyle and Sanskrit, for which Obsidian's Moment has no locale, so it writes English in them.
    public static let choices: [Choice] = {
        let available = Set(Locale.availableIdentifiers)
        let languages = MomentDateLanguageDefinition.all.compactMap { definition -> Choice? in
            let systemIdentifier = definition.systemIdentifier.replacingOccurrences(of: "-", with: "_")
            guard available.contains(systemIdentifier) else { return nil }
            let locale = Locale(identifier: systemIdentifier)
            let name = locale.localizedString(forIdentifier: systemIdentifier) ?? definition.code
            return Choice(id: definition.code, displayName: name.capitalized(with: locale))
        }
        return [Choice(id: english.id, displayName: "English")] + languages.sorted { first, second in first.displayName < second.displayName }
    }()

    private init(english: Void) {
        id = "en"
        months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
        monthsAfterDay = months
        abbreviatedMonths = months.map { name in String(name.prefix(3)) }
        weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        abbreviatedWeekdays = weekdays.map { name in String(name.prefix(3)) }
        shortestWeekdays = weekdays.map { name in String(name.prefix(2)) }
        otherMonthForms = []
        otherAbbreviatedMonthForms = []
        otherWeekdayForms = []
        otherAbbreviatedWeekdayForms = []
        // Moment's English locale: weeks start on Sunday, and week 1 holds January 1.
        firstWeekday = 1
        minimumDaysInFirstWeek = 1
        takesMonthAfterDayOnlyRightAfterIt = false
        ordinalTemplate = "%d"
        ordinalExceptions = [:]
        digits = []
        comma = nil
        ordinalsAreEnglish = true
    }

    private init(_ definition: MomentDateLanguageDefinition) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: definition.systemIdentifier.replacingOccurrences(of: "-", with: "_"))
        // Before the symbols: the language's own calendar, as for Persian or Thai, has other months.
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let systemMonths = formatter.standaloneMonthSymbols ?? MomentDateLanguage.english.months
        let systemMonthsAfterDay = formatter.monthSymbols ?? systemMonths
        let systemWeekdays = formatter.standaloneWeekdaySymbols ?? MomentDateLanguage.english.weekdays
        let systemAbbreviatedMonths = formatter.shortMonthSymbols ?? MomentDateLanguage.english.abbreviatedMonths
        let systemAbbreviatedWeekdays = formatter.shortWeekdaySymbols ?? MomentDateLanguage.english.abbreviatedWeekdays
        id = definition.code
        months = definition.months ?? systemMonths
        monthsAfterDay = definition.monthsAfterDay ?? systemMonthsAfterDay
        abbreviatedMonths = systemAbbreviatedMonths
        weekdays = definition.weekdays ?? systemWeekdays
        abbreviatedWeekdays = systemAbbreviatedWeekdays
        // Moment's two-letter names have no dot; the system's six-letter pattern often does.
        shortestWeekdays = Self.shortestWeekdayNames(using: formatter, abbreviatedWeekdays: systemAbbreviatedWeekdays)
        otherMonthForms = [systemMonths, systemMonthsAfterDay]
        otherAbbreviatedMonthForms = [formatter.shortStandaloneMonthSymbols ?? []]
        otherWeekdayForms = [systemWeekdays, formatter.weekdaySymbols ?? []]
        otherAbbreviatedWeekdayForms = [formatter.shortStandaloneWeekdaySymbols ?? []]
        firstWeekday = definition.firstWeekday
        minimumDaysInFirstWeek = definition.minimumDaysInFirstWeek
        takesMonthAfterDayOnlyRightAfterIt = definition.code == "pl"
        ordinalTemplate = definition.ordinal
        ordinalExceptions = definition.ordinalExceptionsByNumber
        digits = Array(definition.digits ?? "")
        comma = definition.comma
        ordinalsAreEnglish = false
    }

    private static func shortestWeekdayNames(using formatter: DateFormatter, abbreviatedWeekdays: [String]) -> [String] {
        formatter.dateFormat = "EEEEEE"
        return (0..<7).map { weekdayIndex in
            // January 4, 1970 was a Sunday.
            let name = formatter.string(from: Date(timeIntervalSince1970: Double(3 + weekdayIndex) * 86_400 + 43_200))
            return name.hasSuffix(".") ? String(name.dropLast()) : name
        }
    }

    /// The start of every full month name that only one month starts with, three code points or more, which is what Moment's
    /// abbreviations mostly are where they differ from Foundation's: `Sep` for `September`, where Foundation has `Sept`.
    var monthNameBeginnings: [String: Int] {
        var monthsByBeginning: [String: Set<Int>] = [:]
        for forms in [months, monthsAfterDay] + otherMonthForms {
            for (monthIndex, name) in forms.enumerated() where name.count > 1 {
                for length in 1..<name.count {
                    let beginning = name.prefix(length)
                    if beginning.unicodeScalars.count >= 3 { monthsByBeginning[String(beginning).lowercased(), default: []].insert(monthIndex + 1) }
                }
            }
        }
        return monthsByBeginning.compactMapValues { months in months.count == 1 ? months.first : nil }
    }

    /// `number` as Moment's `Do` writes it in this language.
    func ordinal(_ number: Int) -> String {
        if ordinalsAreEnglish { return Self.englishOrdinal(number) }
        return (ordinalExceptions[number] ?? ordinalTemplate).replacingOccurrences(of: "%d", with: String(number))
    }

    private static func englishOrdinal(_ number: Int) -> String {
        let lastTwoDigits = number % 100
        if (11...13).contains(lastTwoDigits) { return "\(number)th" }
        switch number % 10 {
        case 1: return "\(number)st"
        case 2: return "\(number)nd"
        case 3: return "\(number)rd"
        default: return "\(number)th"
        }
    }

    /// `text` as this language's Moment finishes every date: in its own digits, and its own comma.
    func inOwnDigits(_ text: String) -> String {
        guard !digits.isEmpty else { return text }
        return String(text.map { character in
            if let digitValue = character.wholeNumberValue, character.isASCII { return digits[digitValue] }
            return character == "," ? (comma ?? character) : character
        })
    }

    /// What `inOwnDigits` changed, the other way round, for a text to read.
    var westernFormsOfOwnDigits: [Character: Character] {
        var forms: [Character: Character] = [:]
        for (digitValue, digit) in digits.enumerated() { forms[digit] = Character(String(digitValue)) }
        if let comma { forms[comma] = "," }
        return forms
    }
}
