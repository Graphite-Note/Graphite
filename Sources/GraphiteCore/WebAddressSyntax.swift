/**
 * File: WebAddressSyntax.swift
 * ----------------------------
 * Layer: Core
 * Description: Finds web addresses written bare in a line of note text, where the editor shows and follows them as links.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

import Foundation

/// A web address written bare in a line, such as `https://example.com/page` or
/// `www.example.com`, and the address it opens.
public struct BareWebAddress: Equatable, Sendable {
    /// In UTF-16 code units of the line.
    public let range: NSRange
    public let location: URL
}

/// Bare web addresses as the reading view links them: Foundation's Markdown parser follows
/// GFM's autolink extension, so the editor finds the same `http://`, `https://` and `www.`
/// addresses and ends each where GFM does.
public enum WebAddressSyntax {
    private static let candidatePattern = WebAddressSyntaxPattern.candidate.compiled()
    private static let closingParenthesis = UInt16(UInt8(ascii: ")"))
    private static let openingParenthesis = UInt16(UInt8(ascii: "("))
    /// Punctuation that ends a sentence rather than the address: `See https://example.com.`
    private static let trailingPunctuation: Set<UInt16> = Set(".,:;!?*_~'\"".utf16)

    /// The bare addresses within `range` of `line`, in order. A line without `://` or `www.`
    /// is turned away before the pattern runs, so most lines cost two searches.
    public static func addresses(in line: NSString, range: NSRange) -> [BareWebAddress] {
        guard range.length > 0,
              line.range(of: "://", options: .literal, range: range).location != NSNotFound
                || line.range(of: "www.", options: [.literal, .caseInsensitive], range: range).location != NSNotFound else { return [] }
        return candidatePattern.matches(in: line as String, range: range).compactMap { match in
            let addressRange = trimmed(match.range, in: line)
            guard addressRange.length > 0 else { return nil }
            let written = line.substring(with: addressRange)
            let hasScheme = written.range(of: "://") != nil
            // A `www.` address opens over HTTPS; the reading view's Foundation opens it over HTTP,
            // which sites send on to HTTPS.
            guard let location = URL(string: hasScheme ? written : "https://" + written) ?? percentEncodedURL(hasScheme ? written : "https://" + written),
                  location.host?.isEmpty == false else { return nil }
            return BareWebAddress(range: addressRange, location: location)
        }
    }

    /// The bare addresses of a whole line.
    public static func addresses(in line: String) -> [BareWebAddress] {
        let text = line as NSString
        return addresses(in: text, range: NSRange(location: 0, length: text.length))
    }

    /// The candidate without what GFM leaves out at its end: sentence punctuation, and a
    /// closing parenthesis with no opening one in the address, as in `(see https://example.com)`.
    private static func trimmed(_ candidate: NSRange, in line: NSString) -> NSRange {
        var length = candidate.length
        var openingCount = 0
        var closingCount = 0
        for offset in 0..<length {
            let unit = line.character(at: candidate.location + offset)
            if unit == openingParenthesis { openingCount += 1 } else if unit == closingParenthesis { closingCount += 1 }
        }
        while length > 0 {
            let last = line.character(at: candidate.location + length - 1)
            if trailingPunctuation.contains(last) {
                length -= 1
            } else if last == closingParenthesis, closingCount > openingCount {
                closingCount -= 1
                length -= 1
            } else {
                break
            }
        }
        // `https://` alone, or `www.` alone, is not an address.
        let written = line.substring(with: NSRange(location: candidate.location, length: length))
        if written.hasSuffix("://") || written.lowercased() == "www." { return NSRange(location: candidate.location, length: 0) }
        return NSRange(location: candidate.location, length: length)
    }

    /// An address holding characters `URL(string:)` refuses, such as `|` or `^`.
    private static func percentEncodedURL(_ written: String) -> URL? {
        written.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed.union(CharacterSet(charactersIn: "#%"))).flatMap(URL.init(string:))
    }
}

/// The constant patterns of `WebAddressSyntax`; `StaticPatternTests` compiles every case.
enum WebAddressSyntaxPattern: String, StaticPatternSet {
    /// Where GFM starts an address: at the line's start or after a space, `*`, `_`, `~` or `(`;
    /// also after `<`, `[` or a quote. It runs to the next space or angle bracket.
    case candidate = #"(?:^|(?<=[\s*_~(<\["']))(?i:https?://(?=[^\s<>])|www\.(?=[A-Za-z0-9]))[^\s<>]+"#
}
