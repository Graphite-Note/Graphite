/**
 * File: BaseRecordContents.swift
 * ------------------------------
 * Layer: Core
 * Description: What of each file a base can read, so the index loads compact records for a base over a whole vault.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 05/11/2026
 */

import Foundation

/// What of each file a base can read: its properties named anywhere in the base's text,
/// and its tags and links only when the text can ask about them. A base over a whole
/// vault then holds compact records.
///
/// It is read from the text, not the parsed definition, so it never misses a name: a
/// property is kept when its name, ignoring case, appears anywhere in the base. Anything
/// that can read a property whose name the text does not hold keeps every property: the
/// note as a whole (`note`, `file.properties`), a subscript that is not a quoted name,
/// `hasProperty`, links (a property's links are the file's links too), and a view type
/// Graphite does not draw.
public struct BaseRecordContents: Hashable, Sendable {
    public let keepsEveryProperty: Bool
    public let keepsTags: Bool
    public let keepsLinks: Bool
    /// The base's text in lower case; a property whose name it holds is kept.
    private let lowercasedBaseText: String

    /// Every property, tag and link: what `this`, lookups and anything outside a base read.
    public static let everything = BaseRecordContents(keepsEveryProperty: true, keepsTags: true, keepsLinks: true, lowercasedBaseText: "")

    private init(keepsEveryProperty: Bool, keepsTags: Bool, keepsLinks: Bool, lowercasedBaseText: String) {
        self.keepsEveryProperty = keepsEveryProperty
        self.keepsTags = keepsTags
        self.keepsLinks = keepsLinks
        self.lowercasedBaseText = keepsEveryProperty ? "" : lowercasedBaseText
    }

    /// What a base with this source text and these views can read.
    public init(baseSourceText: String, viewTypes: [BaseViewType]) {
        let lowercasedText = baseSourceText.lowercased()
        let keepsLinks = lowercasedText.contains("link") || lowercasedText.contains("embed")
        let drawsOnlyKnownViews = viewTypes.allSatisfy { viewType in
            if case .unsupported = viewType { return false }
            return true
        }
        let readsUnnamedProperties = keepsLinks || !drawsOnlyKnownViews || lowercasedText.contains("properties") || lowercasedText.contains("hasproperty")
            || lowercasedText.range(of: Self.wholeNotePattern, options: .regularExpression) != nil
            || lowercasedText.range(of: Self.computedSubscriptPattern, options: .regularExpression) != nil
        self.init(keepsEveryProperty: readsUnnamedProperties, keepsTags: lowercasedText.contains("tag"), keepsLinks: keepsLinks,
                  lowercasedBaseText: lowercasedText)
    }

    /// `note` read as a whole (`note`, `note.keys()`) rather than through `note.name` or
    /// `note["name"]`.
    private static let wholeNotePattern = #"\bnote\b(?!\s*\[)(?!\s*\.\s*\w+\b(?!\s*\())"#
    /// A subscript whose key is not a quoted name, such as `note[formula.key]` or `list[0]`.
    private static let computedSubscriptPattern = #"[\w)\]]\s*\[\s*[^"'\s]"#

    /// Whether a property with this name is kept. A name with letters outside ASCII is
    /// always kept, since lower-casing it may not give the text's spelling.
    public func keepsProperty(named key: String) -> Bool {
        keepsEveryProperty || !key.unicodeScalars.allSatisfy(\.isASCII) || lowercasedBaseText.contains(key.lowercased())
    }

    /// The record with only what this keeps, as the index would have loaded it.
    public func compacted(_ record: BaseFileRecord) -> BaseFileRecord {
        if self == .everything { return record }
        return BaseFileRecord(path: record.path, size: record.size, createdDate: record.createdDate, modifiedDate: record.modifiedDate,
                              properties: record.properties.filter { entry in keepsProperty(named: entry.key) },
                              tags: keepsTags ? record.tags : [], links: keepsLinks ? record.links : [])
    }
}
