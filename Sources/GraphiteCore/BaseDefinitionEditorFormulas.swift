/**
 * File: BaseDefinitionEditorFormulas.swift
 * ----------------------------------------
 * Layer: Core
 * Description: Edits a .base file's formulas and its top-level text keys (newItemFolder, newItemTemplate), leaving the
 *              rest of the file as written.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import Foundation
import Yams

extension BaseDefinitionEditor {
    /// The top-level keys of a base that hold one text, as Obsidian 1.15 reads them.
    public enum TopLevelTextKey: String, CaseIterable, Sendable {
        case newItemFolder
        case newItemTemplate
    }

    /// Sets the formula `name` to `sourceText`, added after the others when new. A `formulas` entry that is not a
    /// mapping is refused, so nothing written there is lost.
    public mutating func setFormula(named name: String, to sourceText: String) throws {
        var formulas: Node.Mapping
        switch rootMapping["formulas"] {
        case nil:
            formulas = Node.Mapping([])
        case .mapping(let mapping)?:
            formulas = mapping
        case let node? where BaseDefinition.isNullValue(node):
            formulas = Node.Mapping([])
        case .some:
            throw BaseDefinitionEditorError.formulasAreNotAMapping
        }
        formulas[name] = Self.textNode(sourceText)
        rootMapping["formulas"] = .mapping(formulas)
    }

    /// Sets a top-level text key, or removes it for nil or empty text.
    public mutating func setText(_ text: String?, for key: TopLevelTextKey) {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        rootMapping[key.rawValue] = trimmed.isEmpty ? nil : Self.textNode(trimmed)
    }
}

/// Why an edit of a base's formulas was refused.
public enum BaseDefinitionEditorError: Error, Equatable, LocalizedError, Sendable {
    case formulasAreNotAMapping

    public var errorDescription: String? {
        switch self {
        case .formulasAreNotAMapping: "This base's “formulas” is not a list of named formulas, so Graphite left the file unchanged."
        }
    }
}
