/**
 * File: BaseRelation.swift
 * ------------------------
 * Layer: Core
 * Description: A relation between notes in a base: a property whose value is links to notes, how many it holds, and
 *              the value written after notes are chosen.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import Foundation

/// How many notes a relation property takes.
public enum BaseRelationShape: Hashable, Sendable {
    /// One link, for a property the vault declares as text.
    case single
    /// A list of links, as Obsidian writes `course: ["[[VLSI 3]]"]`.
    case list
}

/// A relation is a frontmatter property whose value is links to notes, as in Obsidian. Nothing about it is stored
/// beyond those links (`Docs/Bases-relations-todo.md`, section 1).
public enum BaseRelation {
    /// Of the values the vault gives a property most often, this many are looked at to tell whether they are links.
    public static let examinedVaultValueCount = 5

    /// Whether a property is a relation: its value in the row holds a link to a note, or most of the values the vault
    /// gives it most often (`vaultValues`, most used first, as written) are links to notes.
    public static func isRelation(value: BaseValue?, vaultValues: [String]) -> Bool {
        if let value, !links(in: value).isEmpty { return true }
        let examined = vaultValues.prefix(examinedVaultValueCount)
        guard !examined.isEmpty else { return false }
        let linkCount = examined.filter { text in internalLink(in: text) != nil }.count
        return linkCount * 2 > examined.count
    }

    /// One link or a list: a property declared as text takes one, a declared list, a list value and an empty property
    /// with no declared type take a list, and an undeclared single link stays one until a second note is chosen.
    public static func shape(declaredType: PropertyType?, value: BaseValue?) -> BaseRelationShape {
        switch declaredType {
        case .text: return .single
        case .multitext, .tags, .aliases: return .list
        case .number, .checkbox, .date, .datetime, nil: break
        }
        switch value {
        case .link?, .string?: return .single
        case .list?, .null?, nil: return .list
        case .boolean?, .number?, .date?, .duration?, .file?, .object?, .regularExpression?, .image?, .icon?, .html?: return .list
        }
    }

    /// The links to notes a value holds: a link, or the links of a list, external addresses left out.
    public static func links(in value: BaseValue) -> [BaseLink] {
        switch value {
        case .link(let link): return link.isExternal ? [] : [link]
        case .string(let text): return internalLink(in: text).map { link in [link] } ?? []
        case .list(let elements): return elements.flatMap(links(in:))
        case .null, .boolean, .number, .date, .duration, .file, .object, .regularExpression, .image, .icon, .html: return []
        }
    }

    /// The written items after the choice: `chosen` are the items as written (`[[VLSI 3]]`), kept in the order they
    /// were chosen. One item stays a single value unless the shape is a list. No item clears the property.
    public static func propertyValue(chosen: [String], shape: BaseRelationShape) -> PropertyValue {
        let items = chosen.map { item in item.trimmingCharacters(in: .whitespaces) }.filter { item in !item.isEmpty }
        guard !items.isEmpty else { return .empty }
        if shape == .single, items.count == 1 { return .text(items[0]) }
        return .list(items)
    }

    /// The written item that links to a note named by `target` (without brackets) in the vault's link format.
    public static func writtenItem(target: String) -> String {
        "[[" + target + "]]"
    }

    private static func internalLink(in text: String) -> BaseLink? {
        guard let link = BaseLink.parse(text.trimmingCharacters(in: .whitespaces)), !link.isExternal else { return nil }
        return link
    }
}
