/**
 * File: BaseRollupFormula.swift
 * -----------------------------
 * Layer: Core
 * Description: Writes the Bases formulas of a relation's reverse side and of rollups over related notes, in the
 *              functions Obsidian 1.15 and Graphite both evaluate.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import Foundation

/// Which notes a rollup reads, from a row of the base.
public enum BaseRollupRelation: Hashable, Sendable {
    /// The notes a link property of the row names: an assignment's `course`.
    case linkedBy(property: String)
    /// The notes whose link property names the row: a course's assignments, through their `course`.
    case linkingHere(property: String)
    /// The notes a formula of the base gives, such as a reverse relation written before.
    case formula(name: String)
}

/// What a rollup works out over the related notes.
public enum BaseRollupCalculation: String, CaseIterable, Hashable, Sendable {
    /// The related notes themselves, shown as links.
    case notes
    case count
    case sum
    case average
    case minimum
    case maximum
    /// How many related notes have the property checked.
    case countChecked
    /// The share of related notes with the property checked, as a whole percentage (0 with none).
    case percentChecked

    /// Whether the calculation reads a property of the related notes.
    public var readsProperty: Bool {
        switch self {
        case .notes, .count: false
        case .sum, .average, .minimum, .maximum, .countChecked, .percentChecked: true
        }
    }
}

/// The formula text of a relation's reverse side or of a rollup. Each is an ordinary formula of the `.base` file:
/// nothing is stored in the notes (`Docs/Bases-relations-todo.md`, section 2).
///
/// Obsidian's `file.backlinks` holds links and Graphite's holds files. Both answer `asFile()` with the file (Graphite's
/// file returns itself), and a list's `contains` compares a link with the file it reaches, so the same text evaluates
/// alike in both.
public enum BaseRollupFormula {
    /// The related notes, as a list of files with unresolved links and empty values left out.
    public static func relatedNotes(_ relation: BaseRollupRelation) -> String {
        switch relation {
        case .linkedBy(let property):
            return "list(\(noteProperty(property))).filter(value).map(value.asFile()).filter(value)"
        case .linkingHere(let property):
            return "file.backlinks.map(value.asFile()).filter(value).filter(list(value.properties\(member(property))).contains(file))"
        case .formula(let name):
            return "formula" + member(name)
        }
    }

    /// The rollup's formula: `calculation` over `relation`'s notes, reading `property` of each when the calculation
    /// needs one. Nil when it needs a property and none is given.
    public static func sourceText(relation: BaseRollupRelation, property: String?, calculation: BaseRollupCalculation) -> String? {
        let notes = relatedNotes(relation)
        let readProperty = property.map { name in name.trimmingCharacters(in: .whitespaces) }.flatMap { name in name.isEmpty ? nil : name }
        if calculation.readsProperty && readProperty == nil { return nil }
        let values = readProperty.map { name in "\(notes).map(value.properties\(member(name)))" } ?? notes
        let checked = readProperty.map { name in "\(notes).filter(value.properties\(member(name)) == true)" } ?? notes
        switch calculation {
        case .notes: return notes
        case .count: return "\(notes).length"
        case .sum: return "\(values).sum()"
        case .average: return "\(values).mean()"
        case .minimum: return "\(values).min()"
        case .maximum: return "\(values).max()"
        case .countChecked: return "\(checked).length"
        case .percentChecked: return "if(\(notes).length == 0, 0, (\(checked).length / \(notes).length * 100).round())"
        }
    }

    /// A formula's name, made unique among the base's formulas (`assignments`, `assignments 2`).
    public static func uniqueName(_ name: String, existing: [String]) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let base = trimmed.isEmpty ? "rollup" : trimmed
        let taken = Set(existing.map { existingName in existingName.lowercased() })
        guard taken.contains(base.lowercased()) else { return base }
        var suffix = 2
        while taken.contains("\(base) \(suffix)".lowercased()) { suffix += 1 }
        return "\(base) \(suffix)"
    }

    /// `note.course`, or `note["due date"]` for a name that is not an identifier.
    static func noteProperty(_ name: String) -> String {
        "note" + member(name)
    }

    /// `.name`, or `["name"]` with the quotes escaped when the name is not an identifier.
    static func member(_ name: String) -> String {
        if isIdentifier(name) { return "." + name }
        let escaped = name.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "[\"" + escaped + "\"]"
    }

    private static func isIdentifier(_ name: String) -> Bool {
        guard let first = name.unicodeScalars.first, first == "_" || (first.isASCII && CharacterSet.letters.contains(first)) else { return false }
        return name.unicodeScalars.allSatisfy { scalar in scalar == "_" || (scalar.isASCII && CharacterSet.alphanumerics.contains(scalar)) }
    }
}
