/**
 * File: BaseNewItemNote.swift
 * ---------------------------
 * Layer: Core
 * Description: The note New in a base view makes: its folder, its properties written as frontmatter, and its text
 *              from the base's template.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import Foundation

/// Why New in a base view made no note.
public enum BaseNewItemError: Error, Equatable, LocalizedError, Sendable {
    /// The template's frontmatter is not a mapping Graphite can read, so setting properties over it would rewrite it.
    case unreadableTemplateProperties
    /// The template the base names (`newItemTemplate`) is not in the vault.
    case missingTemplate(String)
    /// The template is not UTF-8 text.
    case templateIsNotText(String)

    public var errorDescription: String? {
        switch self {
        case .unreadableTemplateProperties: "The template's properties are not valid YAML. Fix them in the template first."
        case .missingTemplate(let path): "The base's template “\(path)” is not in this vault."
        case .templateIsNotText(let path): "The base's template “\(path)” is not UTF-8 text."
        }
    }
}

/// Turns a `BaseNewItemPlan` into the note New makes (`Docs/Bases-relations-todo.md`, section 3).
public enum BaseNewItemNote {
    /// The name a new note gets before it is named, as Obsidian names one.
    public static let untitledName = "Untitled"

    /// Where New makes its note: `newItemFolder`, then the folder the filters name, then the template's folder, then
    /// the vault's location for new notes from `currentFile` (the base, or the note it is shown in). Obsidian puts the
    /// template's folder before the filters' one, which files new notes in the Templates folder. A folder no vault
    /// path can name is passed over.
    public static func folder(newItemFolder: String?, filterFolder: String?, templatePath: VaultPath?, newNoteLocation: NewNoteLocation,
                              currentFile: VaultPath) -> VaultPath {
        for written in [newItemFolder, filterFolder] {
            guard let written else { continue }
            let normalized = BaseEvaluator.normalizedFolderPath(written)
            if normalized.isEmpty { return .root }
            if let folder = try? VaultPath(normalized) { return folder } // A folder no path can name: the next choice.
        }
        if let templatePath { return templatePath.parent }
        return (try? newNoteLocation.directory(currentFile: currentFile)) ?? .root // An unnamable setting: the vault's root.
    }

    /// The value as a frontmatter property, its links named by `linkText` (the target without brackets) from the new
    /// note's place. A list's items are written as text, the form Obsidian's list properties take.
    public static func propertyValue(_ value: BaseNewItemValue, linkText: (VaultPath) -> String, calendar: Calendar) -> PropertyValue {
        switch value {
        case .empty: return .empty
        case .text(let text): return .text(text)
        case .number(let number): return .number(number)
        case .boolean(let isTrue): return .checkbox(isTrue)
        case .date(let date):
            let text = BaseDateFormatting.defaultText(for: date, calendar: calendar)
            return date.hasTime ? .dateTime(text) : .date(text)
        case .note, .unresolvedLink: return .text(itemText(value, linkText: linkText, calendar: calendar))
        case .list(let elements): return .list(flattened(elements).map { element in itemText(element, linkText: linkText, calendar: calendar) })
        }
    }

    private static func flattened(_ elements: [BaseNewItemValue]) -> [BaseNewItemValue] {
        elements.flatMap { element -> [BaseNewItemValue] in
            if case .list(let nested) = element { return flattened(nested) }
            return [element]
        }
    }

    private static func itemText(_ value: BaseNewItemValue, linkText: (VaultPath) -> String, calendar: Calendar) -> String {
        switch value {
        case .empty: return ""
        case .text(let text): return text
        case .number(let number): return BaseValue.formatted(number)
        case .boolean(let isTrue): return isTrue ? "true" : "false"
        case .date(let date): return BaseDateFormatting.defaultText(for: date, calendar: calendar)
        case .note(let path, let display): return wikiLink(linkText(path), display: display)
        case .unresolvedLink(let target, let display): return wikiLink(target, display: display)
        case .list(let elements):
            return flattened(elements).map { element in itemText(element, linkText: linkText, calendar: calendar) }.joined(separator: ", ")
        }
    }

    private static func wikiLink(_ target: String, display: String?) -> String {
        "[[" + target + (display.map { text in "|" + text } ?? "") + "]]"
    }

    /// The new note's text: `template` (already filled in) or nothing, with `properties` set over the template's own,
    /// matched by name as a property edit matches it, and added after them otherwise.
    /// - Throws: When the template's frontmatter is not a mapping Graphite can read, so it would be rewritten.
    public static func text(template: String?, properties: [NoteProperty], declaredTypes: [String: PropertyType]) throws -> String {
        let source = template ?? ""
        var merged: [NoteProperty] = []
        if let yaml = BasePropertyEditing.frontmatterYAML(in: source) {
            guard let templateProperties = NoteProperties.parse(yaml, declaredTypes: declaredTypes) else {
                throw BaseNewItemError.unreadableTemplateProperties
            }
            merged = templateProperties
        }
        for property in properties {
            if let index = merged.firstIndex(where: { existing in existing.key.caseInsensitiveCompare(property.key) == .orderedSame }) {
                merged[index].value = property.value
            } else {
                merged.append(property)
            }
        }
        return NoteProperties.replacingFrontmatter(in: source, with: merged, declaredTypes: declaredTypes)
    }
}
