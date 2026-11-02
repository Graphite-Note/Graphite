/**
 * File: MomentDateReader.swift
 * ----------------------------
 * Layer: Core
 * Description: Reads the day a text names in a Moment date format, with the format prepared once for many texts.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import Foundation

/// A Moment date format prepared to read many texts, as the file names of a daily notes folder:
/// the format is split and its pattern compiled once, not for each name.
public struct MomentDateReader: Sendable {
    private let pieces: [MomentDateFormat.Piece]
    private let expression: NSRegularExpression
    private let fields: [String]

    /// nil when the format has a token that names no part of a day to read (hours, for one),
    /// or makes no valid pattern.
    public init?(format: String) {
        let pieces = MomentDateFormat.pieces(of: format)
        var pattern = "^"
        var fields: [String] = []
        for piece in pieces {
            switch piece {
            case .literal(let literal):
                pattern += NSRegularExpression.escapedPattern(for: literal)
            case .token(let token):
                guard let tokenPattern = Self.pattern(of: token) else { return nil }
                pattern += tokenPattern.pattern
                if tokenPattern.isCaptured { fields.append(token) }
            }
        }
        guard let expression = try? NSRegularExpression(pattern: pattern + "$", options: .caseInsensitive) else { return nil } // A malformed format: no date.
        self.pieces = pieces
        self.expression = expression
        self.fields = fields
    }

    private static func pattern(of token: String) -> (pattern: String, isCaptured: Bool)? {
        let monthNames = MomentDateFormat.monthNames, weekdayNames = MomentDateFormat.weekdayNames
        switch token {
        case "YYYY": return ("(\\d{4})", true)
        case "YY": return ("(\\d{2})", true)
        case "MMMM": return ("(" + monthNames.joined(separator: "|") + ")", true)
        case "MMM": return ("(" + monthNames.map { name in String(name.prefix(3)) }.joined(separator: "|") + ")", true)
        case "MM", "DD": return ("(\\d{2})", true)
        case "M", "D": return ("(\\d{1,2})", true)
        case "Do": return ("(\\d{1,2})(?:st|nd|rd|th)", true)
        case "dddd": return ("(?:" + weekdayNames.joined(separator: "|") + ")", false)
        case "ddd": return ("(?:" + weekdayNames.map { name in String(name.prefix(3)) }.joined(separator: "|") + ")", false)
        case "dd": return ("(?:" + weekdayNames.map { name in String(name.prefix(2)) }.joined(separator: "|") + ")", false)
        default: return nil
        }
    }

    /// The day `text` names, or nil when it is not written in the format or names a day that does not exist.
    public func date(from text: String, timeZone: TimeZone = .current) -> Date? {
        let nsText = text as NSString
        guard let match = expression.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)) else { return nil }
        var components = DateComponents()
        let monthNames = MomentDateFormat.monthNames
        for (fieldIndex, field) in fields.enumerated() {
            let captured = nsText.substring(with: match.range(at: fieldIndex + 1))
            switch field {
            case "YYYY": components.year = Int(captured)
            case "YY": components.year = Int(captured).map { twoDigits in twoDigits > 68 ? 1900 + twoDigits : 2000 + twoDigits }
            case "MMMM": components.month = monthNames.firstIndex { name in name.caseInsensitiveCompare(captured) == .orderedSame }.map { index in index + 1 }
            case "MMM":
                components.month = monthNames.firstIndex { name in name.prefix(3).caseInsensitiveCompare(captured) == .orderedSame }.map { index in index + 1 }
            case "MM", "M": components.month = Int(captured)
            case "DD", "D", "Do": components.day = Int(captured)
            default: break
            }
        }
        guard components.year != nil, components.month != nil, components.day != nil else { return nil }
        guard let date = MomentDateFormat.gregorianCalendar(timeZone: timeZone).date(from: components) else { return nil }
        // Written back the same way, or it named a day that does not exist (31 April).
        return MomentDateFormat.string(from: date, pieces: pieces, timeZone: timeZone).caseInsensitiveCompare(text) == .orderedSame ? date : nil
    }
}
