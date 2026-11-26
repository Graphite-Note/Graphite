/**
 * File: NoteIconEditing.swift
 * ---------------------------
 * Layer: Core
 * Description: The edit that sets or removes a note's `icon` property: only the frontmatter is rewritten, every other
 *              property keeps its exact YAML and the text after the frontmatter is left as it is.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import Foundation

public enum NoteIconEditing {
    /// The edit of `noteText` that writes `icon` (`NoteIcon.propertyText`) into the `icon` property, added when the
    /// note has none, or removes the property when `icon` is nil. `selection` moves with the text after the
    /// frontmatter. Throws when the frontmatter is not YAML Graphite can rewrite without changing other properties
    /// (`BasePropertyEditing`); nil when the note already says so.
    public static func edit(setting icon: NoteIcon?, in noteText: String, selection: NSRange,
                            declaredTypes: [String: PropertyType] = [:]) throws -> MarkdownTextEdit? {
        let value = icon.map { chosenIcon in PropertyValue.text(chosenIcon.propertyText) }
        let editedText = try BasePropertyEditing.settingProperty(NoteIcon.propertyKey, to: value, in: noteText, declaredTypes: declaredTypes)
        guard editedText != noteText else { return nil }
        let originalFrontmatterLength = FrontmatterLocator.length(in: noteText as NSString)
        let editedFrontmatterLength = FrontmatterLocator.length(in: editedText as NSString)
        let replacement = (editedText as NSString).substring(to: editedFrontmatterLength)
        let shift = editedFrontmatterLength - originalFrontmatterLength
        let selectionAfter = selection.location >= originalFrontmatterLength
            ? NSRange(location: selection.location + shift, length: selection.length)
            : NSRange(location: editedFrontmatterLength, length: 0)
        return MarkdownTextEdit(range: NSRange(location: 0, length: originalFrontmatterLength), replacement: replacement, selectionAfter: selectionAfter)
    }

    /// The icon the note's `icon` property names, read from its text as it is now; nil without one Graphite draws.
    public static func icon(in noteText: String) -> NoteIcon? {
        let source = noteText as NSString
        let frontmatterLength = FrontmatterLocator.length(in: source)
        guard frontmatterLength > 0,
              let yaml = try? MarkdownSemantics.parse(source.substring(to: frontmatterLength)).frontmatter, // Unparsable frontmatter names no icon.
              let properties = NoteProperties.parse(yaml),
              let property = properties.first(where: { property in property.key.caseInsensitiveCompare(NoteIcon.propertyKey) == .orderedSame }),
              case .text(let text) = property.value else { return nil }
        return NoteIcon(propertyText: text)
    }
}
