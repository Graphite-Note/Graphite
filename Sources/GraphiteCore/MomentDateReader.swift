/**
 * File: MomentDateReader.swift
 * ----------------------------
 * Layer: Core
 * Description: Reads the day a text names in a Moment date format, with the format prepared once for many texts.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 02/11/2026
 */

import Foundation

/// A Moment date format prepared to read many texts, as the file names of a daily notes folder:
/// the format is split and its pattern compiled once, not for each name.
public struct MomentDateReader: Sendable {
    private let expression: NSRegularExpression
    private let fields: [String]
    /// For each token that is a name: what each written form means, as a month, weekday index or day. A form two
    /// languages share keeps both meanings, the earlier language's first.
    private let namesByToken: [String: [String: [Int]]]
    private let writingLanguage: MomentDateLanguage
    private let readsOnlyEnglish: Bool
    private let westernForms: [Character: Character]

    /// Whether the format holds a name in a language, so that a name may read as the same day in another form.
    public var readsNames: Bool { !namesByToken.isEmpty }

    /// nil when the format has a token that names no part of a day to read (hours, for one),
    /// or makes no valid pattern.
    /// - Parameter languages: The languages names are read in, the first winning where two share a form.
    public init?(format: String, languages: [MomentDateLanguage] = [.english]) {
        let readsOnlyEnglish = languages.allSatisfy { language in language == .english }
        let westernForms: [Character: Character] = languages.reduce(into: [:]) { forms, language in
            forms.merge(language.westernFormsOfOwnDigits) { first, _ in first }
        }
        var pattern = "^"
        var fields: [String] = []
        var namesByToken: [String: [String: [Int]]] = [:]
        for piece in MomentDateFormat.pieces(of: format) {
            switch piece {
            case .literal(let literal):
                pattern += NSRegularExpression.escapedPattern(for: literal.precomposedStringWithCanonicalMapping)
            case .token(let token):
                if let names = Self.names(of: token, languages: languages, westernForms: westernForms) {
                    namesByToken[token] = names
                    var alternatives = names.keys.sorted { first, second in first.count > second.count }
                        .map { name in NSRegularExpression.escapedPattern(for: name) }
                    // A weekday adds nothing to the day, and another writer's abbreviation should not lose the note.
                    if !readsOnlyEnglish, token == "ddd" || token == "dd" { alternatives.append("\\S{1,12}?") }
                    pattern += "(" + alternatives.joined(separator: "|") + ")"
                } else {
                    guard let numberPattern = Self.numberPattern(of: token) else { return nil }
                    pattern += numberPattern
                }
                fields.append(token)
            }
        }
        guard let expression = try? NSRegularExpression(pattern: pattern + "$", options: .caseInsensitive) else { return nil } // A malformed format: no date.
        self.expression = expression
        self.fields = fields
        self.namesByToken = namesByToken
        writingLanguage = languages.first ?? .english
        self.readsOnlyEnglish = readsOnlyEnglish
        self.westernForms = westernForms
    }

    private static func numberPattern(of token: String) -> String? {
        switch token {
        case "YYYY": "(\\d{4})"
        case "YY", "MM", "DD": "(\\d{2})"
        case "M", "D": "(\\d{1,2})"
        default: nil
        }
    }

    private static func names(of token: String, languages: [MomentDateLanguage], westernForms: [Character: Character]) -> [String: [Int]]? {
        let formsOfLanguage: (MomentDateLanguage) -> [[String]]
        switch token {
        case "MMMM": formsOfLanguage = { language in [language.months, language.monthsAfterDay] + language.otherMonthForms }
        case "MMM":
            formsOfLanguage = { language in
                [language.abbreviatedMonths] + language.otherAbbreviatedMonthForms + (language == .english ? [] : [language.months, language.monthsAfterDay])
            }
        case "dddd": formsOfLanguage = { language in [language.weekdays] + language.otherWeekdayForms }
        case "ddd": formsOfLanguage = { language in [language.abbreviatedWeekdays] + language.otherAbbreviatedWeekdayForms }
        case "dd": formsOfLanguage = { language in [language.shortestWeekdays] }
        case "Do": formsOfLanguage = { language in [(1...31).map { day in language.ordinal(day) }] }
        default: return nil
        }
        let startsAtZero = token.hasPrefix("d")
        var names: [String: [Int]] = [:]
        func add(_ name: String, meaning: Int) {
            let key = String(normalizedName(name).map { character in westernForms[character] ?? character })
            if names[key]?.contains(meaning) != true { names[key, default: []].append(meaning) }
        }
        for language in languages {
            for forms in formsOfLanguage(language) {
                for (index, name) in forms.enumerated() where !name.isEmpty {
                    let meaning = startsAtZero ? index : index + 1
                    add(name, meaning: meaning)
                    // An abbreviation is written with its dot by one writer and without by the other.
                    if token == "MMM" || token == "ddd" {
                        if name.hasSuffix(".") { add(String(name.dropLast()), meaning: meaning) } else { add(name + ".", meaning: meaning) }
                    }
                }
            }
            if token == "MMM", language != .english {
                for (beginning, month) in language.monthNameBeginnings where names[normalizedName(beginning)] == nil {
                    add(beginning, meaning: month)
                    add(beginning + ".", meaning: month)
                }
            }
        }
        return names
    }

    /// One spelling for a name as it is written and as it is read: precomposed, in lower case.
    private static func normalizedName(_ name: String) -> String {
        name.precomposedStringWithCanonicalMapping.lowercased()
    }

    /// The day `text` names, or nil when it is not written in the format or names a day that does not exist.
    public func date(from text: String, timeZone: TimeZone = .current) -> Date? {
        let readable = readsOnlyEnglish ? text : String(text.precomposedStringWithCanonicalMapping.map { character in
            westernForms[character] ?? character
        })
        let nsText = readable as NSString
        guard let match = expression.firstMatch(in: readable, range: NSRange(location: 0, length: nsText.length)) else { return nil }
        var components = DateComponents()
        var captures: [(token: String, text: String, nameMeanings: [Int])] = []
        for (fieldIndex, field) in fields.enumerated() {
            let captured = nsText.substring(with: match.range(at: fieldIndex + 1))
            let meanings = namesByToken[field].flatMap { names in names[Self.normalizedName(captured)] } ?? []
            captures.append((field, captured, meanings))
            switch field {
            case "YYYY": components.year = Int(captured)
            case "YY": components.year = Int(captured).map { twoDigits in twoDigits > 68 ? 1900 + twoDigits : 2000 + twoDigits }
            case "MMMM", "MMM": components.month = meanings.first
            case "MM", "M": components.month = Int(captured)
            case "DD", "D": components.day = Int(captured)
            case "Do": components.day = meanings.first
            default: break
            }
        }
        guard components.year != nil, components.month != nil, components.day != nil else { return nil }
        let calendar = MomentDateFormat.gregorianCalendar(timeZone: timeZone)
        guard let date = calendar.date(from: components) else { return nil }
        let everyPartFits = captures.allSatisfy { capture in
            Self.capture(capture, fits: date, calendar: calendar, timeZone: timeZone, language: writingLanguage)
        }
        return everyPartFits ? date : nil
    }

    /// Whether a part read is what the day has: otherwise it named a day that does not exist (31 April, or a wrong weekday).
    private static func capture(_ capture: (token: String, text: String, nameMeanings: [Int]), fits date: Date, calendar: Calendar, timeZone: TimeZone,
                                language: MomentDateLanguage) -> Bool {
        let dayParts = calendar.dateComponents([.month, .day, .weekday], from: date)
        switch capture.token {
        case "MMMM", "MMM": return dayParts.month.map(capture.nameMeanings.contains) ?? false
        case "dddd": return dayParts.weekday.map { weekday in capture.nameMeanings.contains(weekday - 1) } ?? false
        case "ddd", "dd":
            return capture.nameMeanings.isEmpty || dayParts.weekday.map { weekday in capture.nameMeanings.contains(weekday - 1) } ?? false
        case "Do": return dayParts.day.map(capture.nameMeanings.contains) ?? false
        default:
            let written = MomentDateFormat.value(of: capture.token, for: date, calendar: calendar, timeZone: timeZone, language: language, monthFollowsDay: false)
            return written == capture.text
        }
    }
}
