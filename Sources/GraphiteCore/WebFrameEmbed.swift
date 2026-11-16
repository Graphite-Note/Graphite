/**
 * File: WebFrameEmbed.swift
 * -------------------------
 * Layer: Core
 * Description: A web page a note shows in a frame (`<iframe>`): its address, size and look, read from the tag as written.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

import Foundation

/// A web page shown in a note, as Obsidian shows an `<iframe>` written on lines of its own: the page at `address`,
/// in a frame of the tag's size, with the border and rounded corners of its `style`. The note keeps the tag as
/// written; this is only how it reads (`WebFrameSyntax`).
public struct WebFrameEmbed: Hashable, Sendable {
    /// A frame's width, as the tag gives it.
    public enum Width: Hashable, Sendable {
        case points(Double)
        /// A part of the note's column, `1` for `100%`.
        case fractionOfColumn(Double)
    }

    /// A colour of the frame's border, each component from 0 to 1.
    public struct Color: Hashable, Sendable {
        public let red: Double
        public let green: Double
        public let blue: Double
        public let alpha: Double
    }

    /// The line around the frame. Its colour is nil when the style names none, or one Graphite does not read: the
    /// note's own secondary colour is drawn then, as a browser draws the text's colour.
    public struct Border: Hashable, Sendable {
        public let width: Double
        public let color: Color?
    }

    /// As a browser makes a frame that gives no size.
    public static let defaultWidth: Double = 300
    public static let defaultHeight: Double = 150

    public let address: URL
    public let width: Width?
    public let height: Double?
    /// Nil when the style draws none.
    public let border: Border?
    public let cornerRadius: Double
    public let title: String?

    public init(address: URL, width: Width? = nil, height: Double? = nil, border: Border? = nil, cornerRadius: Double = 0, title: String? = nil) {
        self.address = address
        self.width = width
        self.height = height
        self.border = border
        self.cornerRadius = cornerRadius
        self.title = title
    }

    /// The frame's height in points: the tag's, else a browser's 150.
    public var shownHeight: Double { height ?? Self.defaultHeight }

    /// The frame's width in points in a column `columnWidth` wide, never wider than the column.
    public func shownWidth(columnWidth: Double) -> Double {
        let column = max(1, columnWidth)
        switch width {
        case .points(let points): return min(points, column)
        case .fractionOfColumn(let fraction): return min(column, max(1, column * fraction))
        case nil: return min(Self.defaultWidth, column)
        }
    }

    /// What the frame is called, for VoiceOver and the placeholder: its `title`, else its address.
    public var name: String { title ?? address.absoluteString }

    /// The site the page comes from, shown while it loads and when it cannot.
    public var siteName: String { address.host() ?? address.absoluteString }
}

/// Finds a web frame in note source: an `<iframe …></iframe>` written on lines of its own (or alone in a list item),
/// attributes in any order and letter case, quoted with `"` or `'` or unquoted, with its closing tag at the end of the
/// same or a later line. Only an `http:` or `https:` address is a frame; any other `src`, and a frame with none, stay
/// text. The reading view's blocks (`NotePreviewDocument`) and Live Preview's (`LivePreviewBlockScanner`) both ask here,
/// so the two views agree.
public enum WebFrameSyntax {
    /// A tag longer than this many lines is not looked at further: an `<iframe` left open does not make every line
    /// below it read again.
    static let maximumLineCount = 24
    /// Sizes past this are not a page's and are not taken.
    static let largestLength: Double = 10_000

    /// Whether some text may hold a frame, as a callout's lines may: a quick look, before its blocks are found.
    public static func mayHoldFrame(_ text: String) -> Bool {
        text.range(of: "<iframe", options: [.caseInsensitive, .literal]) != nil
    }

    /// The frame whose tag opens on line `firstLineIndex` of `lineCount` lines, and the line its closing tag ends.
    /// A blank line ends an HTML block, so a tag is not looked for past one.
    public static func frame(startingAt firstLineIndex: Int, lineCount: Int, line: (Int) -> String) -> (frame: WebFrameEmbed, lastLineIndex: Int)? {
        let firstLine = line(firstLineIndex)
        guard firstLine.contains("<"), let tagStart = tagStart(onFirstLine: firstLine) else { return nil }
        var text = String(firstLine[tagStart...])
        var lineIndex = firstLineIndex
        while true {
            switch parsedFrame(in: text) {
            case .frame(let frame): return (frame, lineIndex)
            case .notAFrame: return nil
            case .needsMoreLines:
                lineIndex += 1
                guard lineIndex < lineCount, lineIndex - firstLineIndex < maximumLineCount else { return nil }
                let nextLine = line(lineIndex)
                guard !nextLine.allSatisfy(\.isWhitespace) else { return nil }
                text += "\n" + nextLine
            }
        }
    }

    /// Where `<iframe` starts on a line that opens with it, after its indentation or a list item's marker.
    private static func tagStart(onFirstLine line: String) -> String.Index? {
        var index = line.startIndex
        func skipSpaces() { while index < line.endIndex, line[index] == " " || line[index] == "\t" { index = line.index(after: index) } }
        skipSpaces()
        if index < line.endIndex, line[index] != "<" {
            // A list item's marker, then at least one space: the frame stands for the whole item, as an embed does.
            if "-*+".contains(line[index]) {
                index = line.index(after: index)
            } else {
                var digitCount = 0
                while index < line.endIndex, line[index].isASCII, line[index].isNumber, digitCount < 10 {
                    index = line.index(after: index)
                    digitCount += 1
                }
                guard digitCount > 0, digitCount < 10, index < line.endIndex, line[index] == "." || line[index] == ")" else { return nil }
                index = line.index(after: index)
            }
            guard index < line.endIndex, line[index] == " " || line[index] == "\t" else { return nil }
            skipSpaces()
        }
        let opening = "<iframe"
        guard line[index...].lowercased().hasPrefix(opening) else { return nil }
        let afterName = line.index(index, offsetBy: opening.count)
        guard afterName == line.endIndex || line[afterName].isWhitespace || line[afterName] == ">" || line[afterName] == "/" else { return nil }
        return index
    }

    private enum ParseOutcome {
        case frame(WebFrameEmbed)
        case notAFrame
        case needsMoreLines
    }

    /// Reads `<iframe …>…</iframe>` from the start of `text`, which may run over several lines.
    private static func parsedFrame(in text: String) -> ParseOutcome {
        let characters = Array(text)
        var index = "<iframe".count
        var attributes: [String: String] = [:]
        // The opening tag's attributes, up to its `>`.
        while true {
            while index < characters.count, characters[index].isWhitespace || characters[index] == "/" { index += 1 }
            guard index < characters.count else { return .needsMoreLines }
            if characters[index] == ">" { index += 1; break }
            let nameStart = index
            while index < characters.count, !characters[index].isWhitespace, !"/>=\"'".contains(characters[index]) { index += 1 }
            guard index > nameStart else { return .notAFrame }
            let name = String(characters[nameStart..<index]).lowercased()
            while index < characters.count, characters[index].isWhitespace { index += 1 }
            var attributeValue = ""
            if index < characters.count, characters[index] == "=" {
                index += 1
                while index < characters.count, characters[index].isWhitespace { index += 1 }
                guard index < characters.count else { return .needsMoreLines }
                if characters[index] == "\"" || characters[index] == "'" {
                    let quote = characters[index]
                    guard let closingQuote = characters[(index + 1)...].firstIndex(of: quote) else { return .needsMoreLines }
                    attributeValue = String(characters[(index + 1)..<closingQuote])
                    index = closingQuote + 1
                } else {
                    let valueStart = index
                    while index < characters.count, !characters[index].isWhitespace, characters[index] != ">" { index += 1 }
                    attributeValue = String(characters[valueStart..<index])
                }
            }
            // As in HTML, the first of two attributes of one name counts.
            if attributes[name] == nil { attributes[name] = HTMLEntities.decoded(attributeValue) }
        }
        // The closing tag, which must end its line; what is between the tags is the page's fallback text, not shown.
        let rest = String(characters[index...])
        guard let closingRange = rest.range(of: "</iframe", options: .caseInsensitive) else { return .needsMoreLines }
        var afterClosing = closingRange.upperBound
        while afterClosing < rest.endIndex, rest[afterClosing] == " " || rest[afterClosing] == "\t" { afterClosing = rest.index(after: afterClosing) }
        guard afterClosing < rest.endIndex, rest[afterClosing] == ">" else { return .notAFrame }
        guard rest[rest.index(after: afterClosing)...].allSatisfy({ character in character == " " || character == "\t" }) else { return .notAFrame }
        return frame(from: attributes).map(ParseOutcome.frame) ?? .notAFrame
    }

    /// The frame the attributes describe; nil without an `http:` or `https:` address (decision 1). The style's
    /// `width`, `height`, `border` and `border-radius` are read and win over the attributes, as in a browser; any
    /// other style is left out (decision 4).
    static func frame(from attributes: [String: String]) -> WebFrameEmbed? {
        guard let source = attributes["src"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              let address = URL(string: source), let scheme = address.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = address.host(), !host.isEmpty else { return nil }
        let style = WebFrameStyle(attributes["style"] ?? "")
        let width = style.width ?? attributes["width"].flatMap { value in WebFrameStyle.width(of: value, allowsUnitless: true) }
        let height = style.height ?? attributes["height"].flatMap { value in WebFrameStyle.points(of: value, allowsUnitless: true) }
        let title = attributes["title"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return WebFrameEmbed(address: address, width: width, height: height, border: style.border, cornerRadius: style.cornerRadius ?? 0,
                             title: title?.isEmpty == false ? title : nil)
    }
}

/// The few declarations of a frame's `style` that Graphite reads (decision 4).
struct WebFrameStyle {
    var width: WebFrameEmbed.Width?
    var height: Double?
    var border: WebFrameEmbed.Border?
    var cornerRadius: Double?

    init(_ style: String) {
        for declaration in style.split(separator: ";") {
            let parts = declaration.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let property = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = parts[1].replacingOccurrences(of: "!important", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            switch property {
            case "width": width = Self.width(of: value, allowsUnitless: false) ?? width
            case "height": height = Self.points(of: value, allowsUnitless: false) ?? height
            case "border": border = Self.border(of: value)
            case "border-radius": cornerRadius = value.split(separator: " ").first.flatMap { first in Self.points(of: String(first), allowsUnitless: false) } ?? cornerRadius
            default: continue
            }
        }
    }

    /// A length in pixels, which are points; unitless as an HTML attribute writes it. Nil for other units.
    static func points(of value: String, allowsUnitless: Bool) -> Double? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let number: Double?
        if trimmed.hasSuffix("px") {
            number = Double(trimmed.dropLast(2).trimmingCharacters(in: .whitespaces))
        } else {
            // CSS reads a unitless zero as a length too.
            number = allowsUnitless || trimmed == "0" ? Double(trimmed) : nil
        }
        guard let number, number.isFinite, number >= 0, number <= WebFrameSyntax.largestLength else { return nil }
        return number
    }

    static func width(of value: String, allowsUnitless: Bool) -> WebFrameEmbed.Width? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("%") {
            guard let percent = Double(trimmed.dropLast().trimmingCharacters(in: .whitespaces)), percent.isFinite, percent > 0, percent <= 1_000 else { return nil }
            return .fractionOfColumn(percent / 100)
        }
        return points(of: trimmed, allowsUnitless: allowsUnitless).flatMap { points in points > 0 ? .points(points) : nil }
    }

    /// The `border` shorthand: a width, a style and a colour in any order. As in CSS, no line is drawn without a
    /// style, or with `none` or `hidden`; a style with no width is `medium`, three points.
    static func border(of value: String) -> WebFrameEmbed.Border? {
        var width: Double?
        var color: WebFrameEmbed.Color?
        var hasVisibleStyle = false
        for token in tokens(of: value) {
            let lowered = token.lowercased()
            if ["none", "hidden"].contains(lowered) { return nil }
            if ["solid", "dashed", "dotted", "double", "groove", "ridge", "inset", "outset"].contains(lowered) {
                hasVisibleStyle = true
            } else if let keywordWidth = ["thin": 1.0, "medium": 3.0, "thick": 5.0][lowered] {
                width = keywordWidth
            } else if let points = points(of: lowered, allowsUnitless: false) {
                width = points
            } else if let parsedColor = WebFrameColors.color(of: lowered) {
                color = parsedColor
            }
        }
        let shownWidth = width ?? 3
        guard hasVisibleStyle, shownWidth > 0 else { return nil }
        return WebFrameEmbed.Border(width: min(shownWidth, 100), color: color)
    }

    /// The words of a value, with a function such as `rgb(0, 0, 0)` kept whole.
    private static func tokens(of value: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var depth = 0
        for character in value {
            if character == "(" { depth += 1 } else if character == ")" { depth = max(0, depth - 1) }
            if character.isWhitespace, depth == 0 {
                if !current.isEmpty { tokens.append(current) }
                current = ""
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }
}

/// The CSS colours a frame's border is written with: `#rgb`, `#rgba`, `#rrggbb`, `#rrggbbaa`, `rgb()`, `rgba()` and
/// the common names.
enum WebFrameColors {
    private static let namedHex: [String: String] = [
        "black": "000000", "white": "ffffff", "gray": "808080", "grey": "808080", "silver": "c0c0c0", "lightgray": "d3d3d3",
        "lightgrey": "d3d3d3", "darkgray": "a9a9a9", "darkgrey": "a9a9a9", "gainsboro": "dcdcdc", "red": "ff0000", "green": "008000",
        "blue": "0000ff", "orange": "ffa500", "purple": "800080", "yellow": "ffff00", "navy": "000080", "teal": "008080",
    ]

    static func color(of value: String) -> WebFrameEmbed.Color? {
        let lowered = value.lowercased()
        if lowered == "transparent" { return WebFrameEmbed.Color(red: 0, green: 0, blue: 0, alpha: 0) }
        if let hex = namedHex[lowered] { return color(ofHex: hex) }
        if lowered.hasPrefix("#") { return color(ofHex: String(lowered.dropFirst())) }
        if lowered.hasPrefix("rgb"), let open = lowered.firstIndex(of: "("), lowered.hasSuffix(")") {
            let arguments = lowered[lowered.index(after: open)..<lowered.index(before: lowered.endIndex)]
                .split(whereSeparator: { character in character == "," || character == " " || character == "/" })
                .map(String.init)
            guard arguments.count == 3 || arguments.count == 4 else { return nil }
            let channels = arguments.prefix(3).compactMap { argument -> Double? in
                if argument.hasSuffix("%") { return Double(argument.dropLast()).map { percent in percent / 100 } }
                return Double(argument).map { channel in channel / 255 }
            }
            guard channels.count == 3 else { return nil }
            var alpha = 1.0
            if arguments.count == 4 {
                let argument = arguments[3]
                guard let parsedAlpha = argument.hasSuffix("%") ? Double(argument.dropLast()).map({ percent in percent / 100 }) : Double(argument) else { return nil }
                alpha = parsedAlpha
            }
            func clamped(_ component: Double) -> Double { min(1, max(0, component)) }
            return WebFrameEmbed.Color(red: clamped(channels[0]), green: clamped(channels[1]), blue: clamped(channels[2]), alpha: clamped(alpha))
        }
        return nil
    }

    private static func color(ofHex hex: String) -> WebFrameEmbed.Color? {
        guard [3, 4, 6, 8].contains(hex.count), hex.allSatisfy(\.isHexDigit) else { return nil }
        let digits = hex.count <= 4 ? hex.map { digit in String([digit, digit]) } : stride(from: 0, to: hex.count, by: 2).map { offset in
            String(hex[hex.index(hex.startIndex, offsetBy: offset)..<hex.index(hex.startIndex, offsetBy: offset + 2)])
        }
        let components = digits.compactMap { pair in UInt8(pair, radix: 16).map { byte in Double(byte) / 255 } }
        guard components.count == digits.count else { return nil }
        return WebFrameEmbed.Color(red: components[0], green: components[1], blue: components[2], alpha: components.count == 4 ? components[3] : 1)
    }
}

/// The character references an attribute value can hold, such as the `&amp;` between a video address's parameters.
enum HTMLEntities {
    private static let named: [String: String] = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}"]

    static func decoded(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var output = ""
        var index = text.startIndex
        while index < text.endIndex {
            guard text[index] == "&", let semicolon = text[index...].prefix(12).firstIndex(of: ";") else {
                output.append(text[index])
                index = text.index(after: index)
                continue
            }
            let name = String(text[text.index(after: index)..<semicolon])
            if let replacement = replacement(forReference: name) {
                output += replacement
                index = text.index(after: semicolon)
            } else {
                output.append(text[index])
                index = text.index(after: index)
            }
        }
        return output
    }

    private static func replacement(forReference name: String) -> String? {
        if let named = named[name.lowercased()] { return named }
        guard name.hasPrefix("#") else { return nil }
        let number = name.dropFirst()
        let codePoint = number.lowercased().hasPrefix("x") ? UInt32(number.dropFirst(), radix: 16) : UInt32(number, radix: 10)
        return codePoint.flatMap(Unicode.Scalar.init).map { scalar in String(Character(scalar)) }
    }
}
