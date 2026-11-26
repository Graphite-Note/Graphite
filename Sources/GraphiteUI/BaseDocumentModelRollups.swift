/**
 * File: BaseDocumentModelRollups.swift
 * ------------------------------------
 * Layer: UI
 * Description: Saves a rollup into a .base file: its formula, the formula of the reverse relation it reads, and a
 *              column of the selected view.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import Foundation
import GraphiteCore

/// A rollup as the builder describes it, before it is written (`BaseRollupFormula`).
struct BaseRollupDraft: Hashable {
    var name: String
    var relation: BaseRollupRelation
    var property: String
    var calculation: BaseRollupCalculation

    /// The name of the formula that holds the notes linking here through `property`, when the base has none yet.
    static func reverseRelationName(property: String) -> String { property + " backlinks" }

    /// The rollup's formula, reading the reverse relation through `reverseFormulaName` when it goes through one.
    func sourceText(reverseFormulaName: String?) -> String? {
        let through: BaseRollupRelation
        switch relation {
        case .linkingHere where calculation != .notes:
            guard let reverseFormulaName else { return nil }
            through = .formula(name: reverseFormulaName)
        case .linkingHere, .linkedBy, .formula:
            through = relation
        }
        return BaseRollupFormula.sourceText(relation: through, property: calculation.readsProperty ? property : nil, calculation: calculation)
    }
}

extension BaseDocumentModel {
    /// The base's formulas a rollup can read through: those that follow links (`asFile()`) or backlinks, which the
    /// builder writes for a relation. Only offered as choices: a formula of another kind reads as an empty list.
    var noteListFormulaNames: [String] {
        (definition?.formulas ?? []).filter { formula in
            formula.sourceText.contains("backlinks") || formula.sourceText.contains("asFile()")
        }.map(\.name)
    }

    /// The name of a formula of the base holding `sourceText` already, so a relation is written once.
    func formulaName(holding sourceText: String) -> String? {
        definition?.formulas.first { formula in formula.sourceText == sourceText }?.name
    }

    /// Writes the rollup's formula, and for a rollup over notes linking here the formula of that reverse relation when
    /// the base has none, then shows it as the last column of the selected view. One revision-checked save.
    /// - Returns: Whether the base was saved.
    @discardableResult
    func addRollup(_ draft: BaseRollupDraft) async -> Bool {
        guard let definition, let view = selectedView else { return false }
        let existingNames = definition.formulas.map(\.name)
        var reverseFormula: BaseFormula?
        var reverseFormulaName: String?
        if case .linkingHere(let property) = draft.relation, draft.calculation != .notes {
            let reverseText = BaseRollupFormula.relatedNotes(draft.relation)
            if let existing = formulaName(holding: reverseText) {
                reverseFormulaName = existing
            } else {
                let name = BaseRollupFormula.uniqueName(BaseRollupDraft.reverseRelationName(property: property), existing: existingNames)
                reverseFormula = BaseFormula(name: name, sourceText: reverseText)
                reverseFormulaName = name
            }
        }
        guard let sourceText = draft.sourceText(reverseFormulaName: reverseFormulaName) else { return false }
        let rollupName = BaseRollupFormula.uniqueName(draft.name, existing: existingNames + [reverseFormula?.name].compactMap { name in name })
        let viewPosition = view.id
        let reverseFormulaToWrite = reverseFormula
        let order = view.visibleProperties + [.formula(rollupName)]
        return await editDefinition(target: BaseViewTarget(view)) { editor -> Bool in
            if let reverseFormulaToWrite { try editor.setFormula(named: reverseFormulaToWrite.name, to: reverseFormulaToWrite.sourceText) }
            try editor.setFormula(named: rollupName, to: sourceText)
            try editor.setOrder(order, forViewAt: viewPosition)
            return true
        } != nil
    }

    /// Writes `newItemFolder` and `newItemTemplate`, the keys Obsidian's New reads.
    /// - Returns: Whether the base was saved.
    @discardableResult
    func setNewItemSettings(folder: String, template: String) async -> Bool {
        await editDefinition { editor -> Bool in
            editor.setText(folder, for: .newItemFolder)
            editor.setText(template, for: .newItemTemplate)
            return true
        } != nil
    }
}
