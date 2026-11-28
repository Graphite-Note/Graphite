/**
 * File: NoteBanner.swift
 * ----------------------
 * Layer: Core
 * Description: A note's cover picture as the Banners and Pixel Banner plugins write it in the `banner` property,
 *              with the vertical position both plugins keep, read once into a value the reading view draws.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 28/11/2026
 */

import Foundation
import Yams

/// The cover picture of a note, from its `banner` property.
public struct NoteBanner: Hashable, Sendable {
    /// Where the picture is.
    public enum Source: Hashable, Sendable {
        /// A file of the vault, as a link target: resolved like an embed's target from the note's folder.
        case vaultFile(linkTarget: String)
        /// A picture on the web.
        case webAddress(URL)
    }

    public let source: Source
    /// Which part of the picture shows when it is cropped to the banner's height: 0 its top, 1 its bottom.
    public let verticalFocus: Double

    /// The property that holds the picture, read by both plugins.
    public static let propertyKey = "banner"
    /// Banners' vertical position, from 0 to 1.
    static let bannersVerticalKey = "banner_y"
    /// Pixel Banner's vertical position, a percentage.
    static let pixelBannerVerticalKey = "banner-y"
    /// The properties a cover is drawn from, lowercased: the picture and both plugins' positions.
    public static let coverPropertyKeys: Set<String> = [propertyKey, bannersVerticalKey, pixelBannerVerticalKey]
    /// The middle of the picture shows when no position is written.
    public static let defaultVerticalFocus = 0.5

    public init(source: Source, verticalFocus: Double = Self.defaultVerticalFocus) {
        self.source = source
        self.verticalFocus = min(max(verticalFocus, 0), 1)
    }

    /// The banner the properties describe, or nil when `banner` is missing or names no picture Graphite can show:
    /// Pixel Banner's search words, which need its online service, and `file://` paths outside the vault.
    public init?(properties: [NoteProperty]) {
        guard let bannerProperty = properties.first(where: { property in property.key.caseInsensitiveCompare(Self.propertyKey) == .orderedSame }),
              let text = Self.text(of: bannerProperty.value),
              let source = Self.source(ofBannerText: text) else { return nil }
        self.init(source: source, verticalFocus: Self.verticalFocus(in: properties) ?? Self.defaultVerticalFocus)
    }

    /// The picture a `banner` text names: a wikilink or embed (`[[x]]`, `![[x]]`), a Markdown link or embed
    /// (`![](x)`, `[title](x)`), a web address, or a plain path with a picture's file extension.
    static func source(ofBannerText bannerText: String) -> Source? {
        let text = bannerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if let wikiTarget = wikiLinkTarget(in: text) { return .vaultFile(linkTarget: wikiTarget) }
        let destination = markdownLinkDestination(in: text) ?? text
        if let address = URL(string: destination), let scheme = address.scheme?.lowercased() {
            return scheme == "http" || scheme == "https" ? .webAddress(address) : nil
        }
        let path = destination.removingPercentEncoding ?? destination
        let fileExtension = (path as NSString).pathExtension
        guard DocumentKind(fileExtension: fileExtension) == .image else { return nil }
        return .vaultFile(linkTarget: path)
    }

    /// The vertical position Banners (0 to 1) or Pixel Banner (0 to 100) wrote, as a fraction.
    static func verticalFocus(in properties: [NoteProperty]) -> Double? {
        for property in properties {
            guard case .number(let number) = property.value else { continue }
            if property.key == bannersVerticalKey { return number }
            if property.key == pixelBannerVerticalKey { return number / 100 }
        }
        return nil
    }

    /// The text of a property's value. YAML reads an unquoted `[[x]]` as a list holding a one-item list, which the
    /// property reader keeps as YAML; its one item is the link's target.
    private static func text(of value: PropertyValue) -> String? {
        switch value {
        case .text(let text): text
        case .unsupported(let yaml): (try? Yams.load(yaml: yaml) as? [[String]]).flatMap(unquotedWikiLinkText(ofNestedList:)) // Other YAML is no banner.
        case .list, .empty, .number, .checkbox, .date, .dateTime: nil
        }
    }

    /// `[[target]]` for the list YAML makes of an unquoted wikilink, a list holding one list of one item.
    private static func unquotedWikiLinkText(ofNestedList nestedList: [[String]]) -> String? {
        guard nestedList.count == 1, nestedList[0].count == 1 else { return nil }
        return "[[\(nestedList[0][0])]]"
    }

    /// The target of `[[target]]`, `![[target]]` or `[[target|alias]]`, without a heading or block part.
    private static func wikiLinkTarget(in text: String) -> String? {
        var body = Substring(text)
        if body.hasPrefix("!") { body = body.dropFirst() }
        guard body.hasPrefix("[["), body.hasSuffix("]]") else { return nil }
        let inner = body.dropFirst(2).dropLast(2)
        let target = inner.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).first ?? inner
        let withoutSubpath = target.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? target
        let trimmed = withoutSubpath.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The destination of `![alt](destination)` or `[title](destination)`, without angle brackets.
    private static func markdownLinkDestination(in text: String) -> String? {
        guard text.hasSuffix(")"), let opening = text.range(of: "](") else { return nil }
        guard text.hasPrefix("[") || text.hasPrefix("![") else { return nil }
        var destination = text[opening.upperBound..<text.index(before: text.endIndex)].trimmingCharacters(in: .whitespaces)
        if destination.hasPrefix("<"), destination.hasSuffix(">") { destination = String(destination.dropFirst().dropLast()) }
        return destination.isEmpty ? nil : destination
    }
}
