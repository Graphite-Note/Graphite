/**
 * File: WebLinkPreview.swift
 * --------------------------
 * Layer: Core
 * Description: YouTube addresses a note embeds as a video card, the title and thumbnail read from a page or from oEmbed,
 *              and the edits that title a bare web address or make it a preview.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

import Foundation

/// A YouTube video or playlist, which `![title](address)` on a line of its own shows as a
/// card, as Obsidian embeds it.
public struct WebVideo: Equatable, Hashable, Sendable {
    public enum Content: Equatable, Hashable, Sendable {
        case video(identifier: String)
        case playlist(identifier: String)
    }

    public let content: Content
    /// The address as written, which a tap on the card opens.
    public let address: URL

    private static let identifierCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
    private static let youTubeHosts: Set<String> = ["youtube.com", "m.youtube.com", "music.youtube.com", "youtube-nocookie.com"]

    /// Nil for an address that is not a YouTube video or playlist.
    public init?(address: URL) {
        guard let scheme = address.scheme?.lowercased(), scheme == "https" || scheme == "http",
              var host = address.host?.lowercased() else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        let pathParts = address.path.split(separator: "/").map(String.init)
        let query = URLComponents(url: address, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func queryValue(_ name: String) -> String? { query.first { item in item.name == name }?.value.flatMap(Self.validIdentifier) }
        if host == "youtu.be", let identifier = pathParts.first.flatMap(Self.validIdentifier) {
            content = .video(identifier: identifier)
        } else if Self.youTubeHosts.contains(host) {
            if pathParts.first == "watch", let identifier = queryValue("v") {
                content = .video(identifier: identifier)
            } else if pathParts.count >= 2, ["shorts", "embed", "live", "v"].contains(pathParts[0]),
                      let identifier = Self.validIdentifier(pathParts[1]) {
                content = .video(identifier: identifier)
            } else if pathParts.first == "playlist", let identifier = queryValue("list") {
                content = .playlist(identifier: identifier)
            } else {
                return nil
            }
        } else {
            return nil
        }
        self.address = address
    }

    /// The video of a Markdown embed (`![title](address)`) written alone on its line; never
    /// one of a wikilink embed, which names a vault file.
    public init?(embed: EmbedReference) {
        guard !embed.isWiki else { return nil }
        let destination = embed.target.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? embed.target
        guard let address = URL(string: destination) else { return nil }
        self.init(address: address)
    }

    public var isPlaylist: Bool {
        if case .playlist = content { return true }
        return false
    }

    /// The thumbnail YouTube serves for a video at a fixed address; a playlist's is known only
    /// from oEmbed.
    public var directThumbnail: URL? {
        guard case .video(let identifier) = content else { return nil }
        return URL(string: "https://i.ytimg.com/vi/\(identifier)/hqdefault.jpg")
    }

    /// YouTube's oEmbed answer for the address: its title and thumbnail, for videos and
    /// playlists alike.
    public var oEmbedRequest: URL? {
        var components = URLComponents(string: "https://www.youtube.com/oembed")
        components?.queryItems = [URLQueryItem(name: "url", value: address.absoluteString), URLQueryItem(name: "format", value: "json")]
        return components?.url
    }

    private static func validIdentifier(_ candidate: String) -> String? {
        guard candidate.count >= 6, candidate.count <= 64, candidate.unicodeScalars.allSatisfy(identifierCharacters.contains) else { return nil }
        return candidate
    }
}

/// What a page says of itself: its title, and a picture for a card.
public struct WebLinkDetails: Equatable, Sendable {
    public let title: String?
    public let thumbnail: URL?

    public init(title: String?, thumbnail: URL?) {
        self.title = title
        self.thumbnail = thumbnail
    }

    /// The most of a page read for its title: the `<head>` comes first, and a page larger than
    /// this is not read to its end.
    public static let maximumPageBytes = 512 * 1024
    private static let ogTitlePattern = WebLinkDetailsPattern.ogTitle.compiled()
    private static let ogTitleAfterContentPattern = WebLinkDetailsPattern.ogTitleAfterContent.compiled()
    private static let titlePattern = WebLinkDetailsPattern.title.compiled()
    private static let numericReferencePattern = WebLinkDetailsPattern.numericReference.compiled()

    /// Reads an oEmbed answer (`{"title": …, "thumbnail_url": …}`); nil when it is not one.
    public static func fromOEmbed(_ data: Data) -> WebLinkDetails? {
        guard let answer = try? JSONDecoder().decode(OEmbedAnswer.self, from: data) else { return nil } // Not oEmbed's JSON ("Not Found"): no details.
        let title = answer.title.map(cleanedTitle).flatMap { title in title.isEmpty ? nil : title }
        let thumbnail = answer.thumbnail_url.flatMap(URL.init(string:))
        guard title != nil || thumbnail != nil else { return nil }
        return WebLinkDetails(title: title, thumbnail: thumbnail)
    }

    /// The fields of an oEmbed answer that a card shows, named as oEmbed names them.
    private struct OEmbedAnswer: Decodable {
        let title: String?
        let thumbnail_url: String?
    }

    /// The page's `og:title`, or else its `<title>`, with HTML's character references read.
    public static func fromHTML(_ html: String) -> WebLinkDetails? {
        let text = html as NSString
        let wholeText = NSRange(location: 0, length: text.length)
        let match = ogTitlePattern.firstMatch(in: html, range: wholeText) ?? ogTitleAfterContentPattern.firstMatch(in: html, range: wholeText)
            ?? titlePattern.firstMatch(in: html, range: wholeText)
        guard let match, match.range(at: 1).location != NSNotFound else { return nil }
        let title = cleanedTitle(decodingCharacterReferences(in: text.substring(with: match.range(at: 1))))
        return title.isEmpty ? nil : WebLinkDetails(title: title, thumbnail: nil)
    }

    /// One line, spaces collapsed.
    private static func cleanedTitle(_ title: String) -> String {
        title.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func decodingCharacterReferences(in text: String) -> String {
        var decoded = text
        for (reference, character) in [("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " ")] {
            decoded = decoded.replacingOccurrences(of: reference, with: character)
        }
        let source = decoded as NSString
        var result = ""
        var lastEnd = 0
        for match in numericReferencePattern.matches(in: decoded, range: NSRange(location: 0, length: source.length)) {
            let digits = source.substring(with: match.range(at: 1))
            let value = digits.lowercased().hasPrefix("x") ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits)
            guard let value, let scalar = Unicode.Scalar(value) else { continue }
            result += source.substring(with: NSRange(location: lastEnd, length: match.range.location - lastEnd)) + String(Character(scalar))
            lastEnd = NSMaxRange(match.range)
        }
        result += source.substring(from: lastEnd)
        // Last, so `&amp;lt;` reads as `&lt;`, as a browser shows it.
        return result.replacingOccurrences(of: "&amp;", with: "&")
    }
}

/// The edits of a bare web address's menu: Use Page Title and Show Preview.
public enum WebLinkEditing {
    private static let listMarkerPrefixPattern = WebLinkDetailsPattern.listMarkerPrefix.compiled()

    /// The bare address at a character of the note, as the editor styles it: not one in code,
    /// math, a link or an embed. Its range is in the whole text.
    public static func bareAddress(at location: Int, in text: NSString) -> BareWebAddress? {
        guard location >= 0, location <= text.length, text.length > 0 else { return nil }
        let lineRange = text.lineRange(for: NSRange(location: min(location, text.length - 1), length: 0))
        let spans = MarkdownStyleScanner.spans(in: text, range: lineRange)
        // A bare address is a link span that is its whole element: a link's label has brackets around it.
        guard let span = spans.first(where: { span in
            span.style == .link && span.inlineElementRange == span.range && (NSLocationInRange(location, span.range) || location == NSMaxRange(span.range))
        }) else { return nil }
        return WebAddressSyntax.addresses(in: text, range: span.range).first { address in address.range == span.range }
    }

    /// `[title](address)` in place of the bare address, the cursor after it.
    public static func titledLink(_ address: BareWebAddress, title: String, in text: NSString) -> MarkdownTextEdit? {
        guard isUnchanged(address, in: text) else { return nil }
        let replacement = "[\(escapedLabel(title))](\(destination(of: address, in: text)))"
        return MarkdownTextEdit(range: address.range, replacement: replacement,
                                selectionAfter: NSRange(location: address.range.location + (replacement as NSString).length, length: 0))
    }

    /// `![title](address)` in place of the bare address, on a line of its own so it is drawn as
    /// a card: line breaks go before and after it where the line has other text.
    public static func preview(_ address: BareWebAddress, title: String, in text: NSString) -> MarkdownTextEdit? {
        guard isUnchanged(address, in: text) else { return nil }
        let lineRange = text.lineRange(for: address.range)
        let before = text.substring(with: NSRange(location: lineRange.location, length: address.range.location - lineRange.location))
        let lineContentEnd = lineRange.location + lineContentLength(of: text.substring(with: lineRange) as NSString)
        let after = text.substring(with: NSRange(location: NSMaxRange(address.range), length: max(0, lineContentEnd - NSMaxRange(address.range))))
        let isAloneBefore = listMarkerPrefixPattern.firstMatch(in: before, range: NSRange(location: 0, length: (before as NSString).length)) != nil
        let isAloneAfter = after.allSatisfy(\.isWhitespace)
        let embed = "![\(escapedLabel(title))](\(destination(of: address, in: text)))"
        let replacement = (isAloneBefore ? "" : "\n") + embed + (isAloneAfter ? "" : "\n")
        let embedEnd = address.range.location + (isAloneBefore ? 0 : 1) + (embed as NSString).length
        return MarkdownTextEdit(range: address.range, replacement: replacement, selectionAfter: NSRange(location: embedEnd, length: 0))
    }

    /// Whether the text still holds the address where it was found, as when the menu opened.
    private static func isUnchanged(_ address: BareWebAddress, in text: NSString) -> Bool {
        NSMaxRange(address.range) <= text.length && bareAddress(at: address.range.location, in: text) == address
    }

    /// The address as written, in `<…>` when it holds parentheses, as Graphite writes a pasted link.
    private static func destination(of address: BareWebAddress, in text: NSString) -> String {
        let written = text.substring(with: address.range)
        let withScheme = written.contains("://") ? written : address.location.absoluteString
        return withScheme.contains("(") || withScheme.contains(")") ? "<\(withScheme)>" : withScheme
    }

    /// A title as a link's text: brackets escaped, and `|`, which a table cell or an embed's
    /// size would read, escaped too.
    private static func escapedLabel(_ title: String) -> String {
        title.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]").replacingOccurrences(of: "|", with: "\\|")
    }

    private static func lineContentLength(of line: NSString) -> Int {
        var length = line.length
        while length > 0, line.character(at: length - 1) == 0x0A || line.character(at: length - 1) == 0x0D { length -= 1 }
        return length
    }
}

/// The constant patterns of `WebLinkDetails` and `WebLinkEditing`; `StaticPatternTests` compiles every case.
enum WebLinkDetailsPattern: String, StaticPatternSet {
    case ogTitle = #"<meta\s[^>]*?property\s*=\s*["']og:title["'][^>]*?\scontent\s*=\s*"([^"]*)""#
    case ogTitleAfterContent = #"<meta\s[^>]*?content\s*=\s*"([^"]*)"[^>]*?\sproperty\s*=\s*["']og:title["']"#
    case title = #"<title[^>]*>([^<]*)</title>"#
    case numericReference = #"&#([xX][0-9A-Fa-f]{1,6}|[0-9]{1,7});"#
    /// What may come before an embed for it to be a block: indentation and a list marker.
    case listMarkerPrefix = #"^\s*(?:(?:[-*+]|[0-9]{1,9}[.)])\s+)?$"#

    var options: NSRegularExpression.Options { [.caseInsensitive] }
}
