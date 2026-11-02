/**
 * File: MomentDateFormat.swift
 * ----------------------------
 * Layer: Core
 * Description: Dates written and read with the format strings Obsidian uses (Moment.js), such as YYYY-MM-DD.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 01/11/2026
 */

import Foundation

/// Dates written with the format strings Obsidian uses (Moment.js), such as
/// `YYYY-MM-DD` or `dddd, MMMM Do YYYY`, in Moment's default English locale, as Obsidian's
/// Templates and Daily notes plugins write them.
public enum MomentDateFormat {
    public static let defaultDateFormat = "YYYY-MM-DD"
    public static let defaultTimeFormat = "HH:mm"

    static let monthNames = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
    static let weekdayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    /// Moment's tokens. `sortedTokens` tries the longest first, so `YYYY` is not read as two `YY`.
    private static let tokens = [
        "YYYYYY", "YYYYY", "YYYY", "YY", "Y", "Qo", "Q", "MMMM", "MMM", "MM", "Mo", "M", "DDDD", "DDDo", "DDD", "DD", "Do", "D",
        "dddd", "ddd", "dd", "do", "d", "E", "e", "ww", "wo", "w", "WW", "Wo", "W", "ggggg", "gggg", "gg", "GGGGG", "GGGG", "GG",
        "HH", "H", "hh", "h", "kk", "k", "mm", "m", "ss", "s", "A", "a", "X", "x", "ZZ", "Z", "zz", "z",
        "SSSSSSSSS", "SSSSSSSS", "SSSSSSS", "SSSSSS", "SSSSS", "SSSS", "SSS", "SS", "S",
        "NNNNN", "NNNN", "NNN", "NN", "N", "yyyy", "yyy", "yy", "yo", "y",
    ]
    private static let sortedTokens = tokens.sorted { first, second in first.count > second.count }
    /// Moment's English long date formats. The lower-case ones are the short forms of the
    /// upper-case ones: month and weekday names cut to three letters, month and day without a leading zero.
    private static let longDateFormats = [
        "LLLL": "dddd, MMMM D, YYYY h:mm A", "LLL": "MMMM D, YYYY h:mm A", "LL": "MMMM D, YYYY",
        "LTS": "h:mm:ss A", "LT": "h:mm A", "L": "MM/DD/YYYY",
        "llll": "ddd, MMM D, YYYY h:mm A", "lll": "MMM D, YYYY h:mm A", "ll": "MMM D, YYYY", "l": "M/D/YYYY",
    ]
    private static let sortedLongDateFormatKeys = longDateFormats.keys.sorted { first, second in first.count > second.count }
    private static let eraNames = (annoDomini: "Anno Domini", beforeChrist: "Before Christ", annoDominiAbbreviation: "AD", beforeChristAbbreviation: "BC")

    enum Piece: Equatable, Sendable {
        case token(String)
        case literal(String)
    }

    /// The date written in `format`.
    public static func string(from date: Date, format: String, timeZone: TimeZone = .current) -> String {
        string(from: date, pieces: pieces(of: format), timeZone: timeZone)
    }

    /// The day a text written in `format` names, for file names such as daily notes. Only
    /// formats made of years, months, days, weekday names and literal text can be read. To
    /// read many names, build a `MomentDateReader` once.
    public static func date(from text: String, format: String, timeZone: TimeZone = .current) -> Date? {
        MomentDateReader(format: format)?.date(from: text, timeZone: timeZone)
    }

    /// The date written with already split pieces.
    static func string(from date: Date, pieces: [Piece], timeZone: TimeZone) -> String {
        let calendar = gregorianCalendar(timeZone: timeZone)
        return pieces.map { piece in
            switch piece {
            case .literal(let text): text
            case .token(let token): value(of: token, for: date, calendar: calendar, timeZone: timeZone)
            }
        }.joined()
    }

    // MARK: Private

    static func gregorianCalendar(timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "en_US_POSIX")
        // Moment's English locale: weeks start on Sunday, and week 1 holds January 1.
        calendar.firstWeekday = 1
        calendar.minimumDaysInFirstWeek = 1
        return calendar
    }

    static func pieces(of format: String) -> [Piece] {
        var pieces: [Piece] = []
        var remaining = Substring(format)
        func appendLiteral(_ text: String) {
            if case .literal(let previous) = pieces.last { pieces[pieces.count - 1] = .literal(previous + text) } else { pieces.append(.literal(text)) }
        }
        while let first = remaining.first {
            if first == "[" {
                let bracketed = bracketedText(startingAt: remaining)
                appendLiteral(bracketed.text)
                remaining = bracketed.rest
            } else if first == "\\" {
                let escaped = escapedText(afterBackslashIn: remaining.dropFirst())
                appendLiteral(escaped.text)
                remaining = escaped.rest
            } else if let longFormat = sortedLongDateFormatKeys.first(where: { key in remaining.hasPrefix(key) }),
                      let expansion = longDateFormats[longFormat] {
                pieces += Self.pieces(of: expansion)
                remaining = remaining.dropFirst(longFormat.count)
            } else if let token = sortedTokens.first(where: { token in remaining.hasPrefix(token) }) {
                pieces.append(.token(token))
                remaining = remaining.dropFirst(token.count)
            } else {
                appendLiteral(String(first))
                remaining = remaining.dropFirst()
            }
        }
        return pieces
    }

    /// Text in brackets is written as it is, up to the first `]`. A second `[` before it means the
    /// first one stands alone, as in Moment.
    private static func bracketedText(startingAt text: Substring) -> (text: String, rest: Substring) {
        let afterOpening = text.dropFirst()
        if let stop = afterOpening.firstIndex(where: { character in character == "]" || character == "[" }), afterOpening[stop] == "]" {
            return (String(afterOpening[..<stop]), afterOpening[afterOpening.index(after: stop)...])
        }
        return ("[", afterOpening)
    }

    /// A backslash writes the token or letter after it as it is. Moment drops every backslash of
    /// such a piece, so `\\` alone writes nothing.
    private static func escapedText(afterBackslashIn text: Substring) -> (text: String, rest: Substring) {
        let written = sortedLongDateFormatKeys.first(where: { key in text.hasPrefix(key) })
            ?? sortedTokens.first(where: { token in text.hasPrefix(token) })
            ?? text.first.map { character in String(character) } ?? ""
        return (written.replacingOccurrences(of: "\\", with: ""), text.dropFirst(written.count))
    }

    private static func value(of token: String, for date: Date, calendar: Calendar, timeZone: TimeZone) -> String {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .nanosecond, .weekday, .weekOfYear, .yearForWeekOfYear], from: date)
        let year = components.year ?? 0, month = components.month ?? 1, day = components.day ?? 1
        let hour = components.hour ?? 0, minute = components.minute ?? 0, second = components.second ?? 0
        let weekdayIndex = (components.weekday ?? 1) - 1
        var isoCalendar = Calendar(identifier: .iso8601)
        isoCalendar.timeZone = timeZone
        let isoComponents = isoCalendar.dateComponents([.weekOfYear, .yearForWeekOfYear], from: date)
        let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
        func padded(_ number: Int, _ width: Int) -> String {
            let digits = String(abs(number))
            return (number < 0 ? "-" : "") + String(repeating: "0", count: max(0, width - digits.count)) + digits
        }
        switch token {
        case "YYYYYY": return (year < 0 ? "-" : "+") + padded(abs(year), 6)
        case "YYYYY": return padded(year, 5)
        case "YYYY": return padded(year, 4)
        case "YY": return padded(year % 100, 2)
        case "Y": return String(year)
        case "Q": return String((month - 1) / 3 + 1)
        case "Qo": return ordinal((month - 1) / 3 + 1)
        case "MMMM": return monthNames[month - 1]
        case "MMM": return String(monthNames[month - 1].prefix(3))
        case "MM": return padded(month, 2)
        case "Mo": return ordinal(month)
        case "M": return String(month)
        case "DDDD": return padded(dayOfYear, 3)
        case "DDDo": return ordinal(dayOfYear)
        case "DDD": return String(dayOfYear)
        case "DD": return padded(day, 2)
        case "Do": return ordinal(day)
        case "D": return String(day)
        case "dddd": return weekdayNames[weekdayIndex]
        case "ddd": return String(weekdayNames[weekdayIndex].prefix(3))
        case "dd": return String(weekdayNames[weekdayIndex].prefix(2))
        case "do": return ordinal(weekdayIndex)
        case "d", "e": return String(weekdayIndex)
        case "E": return String(weekdayIndex == 0 ? 7 : weekdayIndex)
        case "ww": return padded(components.weekOfYear ?? 1, 2)
        case "wo": return ordinal(components.weekOfYear ?? 1)
        case "w": return String(components.weekOfYear ?? 1)
        case "WW": return padded(isoComponents.weekOfYear ?? 1, 2)
        case "Wo": return ordinal(isoComponents.weekOfYear ?? 1)
        case "W": return String(isoComponents.weekOfYear ?? 1)
        case "ggggg": return padded(components.yearForWeekOfYear ?? year, 5)
        case "gggg": return padded(components.yearForWeekOfYear ?? year, 4)
        case "gg": return padded((components.yearForWeekOfYear ?? year) % 100, 2)
        case "GGGGG": return padded(isoComponents.yearForWeekOfYear ?? year, 5)
        case "GGGG": return padded(isoComponents.yearForWeekOfYear ?? year, 4)
        case "GG": return padded((isoComponents.yearForWeekOfYear ?? year) % 100, 2)
        case "HH": return padded(hour, 2)
        case "H": return String(hour)
        case "hh": return padded(hour % 12 == 0 ? 12 : hour % 12, 2)
        case "h": return String(hour % 12 == 0 ? 12 : hour % 12)
        case "kk": return padded(hour == 0 ? 24 : hour, 2)
        case "k": return String(hour == 0 ? 24 : hour)
        case "mm": return padded(minute, 2)
        case "m": return String(minute)
        case "ss": return padded(second, 2)
        case "s": return String(second)
        case let fraction where fraction.allSatisfy({ character in character == "S" }):
            // Moment keeps milliseconds: digits beyond the third are zeros.
            let milliseconds = padded((components.nanosecond ?? 0) / 1_000_000, 3)
            return String((milliseconds + String(repeating: "0", count: 6)).prefix(fraction.count))
        case "A": return hour < 12 ? "AM" : "PM"
        case "a": return hour < 12 ? "am" : "pm"
        case "X": return String(Int(date.timeIntervalSince1970))
        case "x": return String(Int(date.timeIntervalSince1970 * 1000))
        case "Z", "ZZ":
            let offsetMinutes = timeZone.secondsFromGMT(for: date) / 60
            let sign = offsetMinutes < 0 ? "-" : "+"
            return sign + padded(abs(offsetMinutes) / 60, 2) + (token == "Z" ? ":" : "") + padded(abs(offsetMinutes) % 60, 2)
        case "z", "zz": return "" // Moment writes a zone name only for UTC; local times have none.
        case "N", "NN", "NNN", "NNNNN": return year > 0 ? eraNames.annoDominiAbbreviation : eraNames.beforeChristAbbreviation
        case "NNNN": return year > 0 ? eraNames.annoDomini : eraNames.beforeChrist
        case "y", "yy", "yyy", "yyyy": return padded(year > 0 ? year : 1 - year, token.count)
        case "yo": return ordinal(year > 0 ? year : 1 - year)
        default: return token
        }
    }

    private static func ordinal(_ number: Int) -> String {
        let lastTwoDigits = number % 100
        if (11...13).contains(lastTwoDigits) { return "\(number)th" }
        switch number % 10 {
        case 1: return "\(number)st"
        case 2: return "\(number)nd"
        case 3: return "\(number)rd"
        default: return "\(number)th"
        }
    }
}
