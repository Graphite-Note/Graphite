/**
 * File: BaseRollupBuilderSheet.swift
 * ----------------------------------
 * Layer: UI
 * Description: Builds a rollup column of a base: the related notes, the property read from them and the calculation,
 *              with the formula it writes shown before it is saved.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import SwiftUI
import GraphiteCore

/// The ways a rollup reaches its notes that the builder offers.
enum BaseRollupDirection: String, CaseIterable, Identifiable {
    /// Notes that link to the row through one of their properties (a course's assignments).
    case linkingHere
    /// Notes a link property of the row names (an assignment's course).
    case linkedBy
    /// Notes a formula of the base already gives.
    case formula
    var id: String { rawValue }

    var title: String {
        switch self {
        case .linkingHere: "Notes Linking Here"
        case .linkedBy: "Notes This Note Links To"
        case .formula: "Notes of a Formula"
        }
    }
}

/// Builds a rollup: through which notes, which of their properties, and what to work out. Save writes ordinary Bases
/// formulas into the `.base` file and adds the column (`BaseDocumentModel.addRollup`).
struct BaseRollupBuilderSheet: View {
    /// The vault's property names, for the relation and the property read.
    let vaultPropertyNames: [String]
    /// The note properties of this base's rows.
    let rowPropertyNames: [String]
    /// The base's formulas that give notes.
    let noteFormulaNames: [String]
    /// Saves the draft and returns nil, or returns why the base was not saved.
    let save: (BaseRollupDraft) async -> String?
    @Environment(\.dismiss) private var dismiss
    @State private var direction = BaseRollupDirection.linkingHere
    @State private var relationProperty = ""
    @State private var formulaName = ""
    @State private var readProperty = ""
    @State private var calculation = BaseRollupCalculation.count
    @State private var name = ""
    @State private var isSaving = false
    @State private var failureMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                relationSection
                calculationSection
                Section {
                    TextField("Column Name", text: $name, prompt: Text(suggestedName))
                        .literalTextEntry()
                } footer: {
                    if let preview { Text(preview).font(.caption.monospaced()).textSelection(.enabled) }
                }
                if let failureMessage {
                    Section { Label(failureMessage, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add Rollup")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: saveDraft).disabled(isSaving || draft == nil) }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 420)
        #endif
        .interactiveDismissDisabled(isSaving)
    }

    @ViewBuilder private var relationSection: some View {
        Section {
            Picker("Notes", selection: $direction) {
                ForEach(availableDirections) { direction in Text(direction.title).tag(direction) }
            }
            switch direction {
            case .linkingHere:
                propertyPicker("Through Their Property", selection: $relationProperty, names: vaultPropertyNames)
            case .linkedBy:
                propertyPicker("Through This Note's Property", selection: $relationProperty, names: rowPropertyNames)
            case .formula:
                propertyPicker("Formula", selection: $formulaName, names: noteFormulaNames)
            }
        } header: {
            Text("Related Notes")
        } footer: {
            Text(relationFooter)
        }
    }

    @ViewBuilder private var calculationSection: some View {
        Section("Calculate") {
            Picker("Calculation", selection: $calculation) {
                ForEach(BaseRollupCalculation.allCases, id: \.self) { calculation in Text(Self.title(of: calculation)).tag(calculation) }
            }
            if calculation.readsProperty {
                propertyPicker("Of Their Property", selection: $readProperty, names: vaultPropertyNames)
            }
        }
    }

    private func propertyPicker(_ title: String, selection: Binding<String>, names: [String]) -> some View {
        Picker(title, selection: selection) {
            Text("Choose…").tag("")
            ForEach(names, id: \.self) { name in Text(name).tag(name) }
        }
    }

    private var availableDirections: [BaseRollupDirection] {
        noteFormulaNames.isEmpty ? [.linkingHere, .linkedBy] : BaseRollupDirection.allCases
    }

    private var relationFooter: String {
        switch direction {
        case .linkingHere: "The notes whose property links to each row, such as a course's assignments through their course. Nothing is stored in them."
        case .linkedBy: "The notes each row's property links to, such as an assignment's course."
        case .formula: "The notes a formula of this base gives."
        }
    }

    static func title(of calculation: BaseRollupCalculation) -> String {
        switch calculation {
        case .notes: "Show the Notes"
        case .count: "Count"
        case .sum: "Sum"
        case .average: "Average"
        case .minimum: "Minimum"
        case .maximum: "Maximum"
        case .countChecked: "Count Checked"
        case .percentChecked: "Percent Checked"
        }
    }

    private var relation: BaseRollupRelation? {
        switch direction {
        case .linkingHere: relationProperty.isEmpty ? nil : .linkingHere(property: relationProperty)
        case .linkedBy: relationProperty.isEmpty ? nil : .linkedBy(property: relationProperty)
        case .formula: formulaName.isEmpty ? nil : .formula(name: formulaName)
        }
    }

    private var suggestedName: String {
        let subject = direction == .formula ? formulaName : relationProperty
        guard !subject.isEmpty else { return "Rollup" }
        switch calculation {
        case .notes: return subject
        case .count: return subject + " count"
        case .percentChecked: return readProperty.isEmpty ? subject : readProperty + " percent"
        case .countChecked: return readProperty.isEmpty ? subject : readProperty + " count"
        case .sum, .average, .minimum, .maximum: return readProperty.isEmpty ? subject : readProperty + " " + Self.title(of: calculation).lowercased()
        }
    }

    private var draft: BaseRollupDraft? {
        guard let relation, !calculation.readsProperty || !readProperty.isEmpty else { return nil }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        return BaseRollupDraft(name: trimmedName.isEmpty ? suggestedName : trimmedName, relation: relation, property: readProperty, calculation: calculation)
    }

    /// The formula Save writes, the reverse relation's formula read under the name it would get.
    private var preview: String? {
        guard let draft else { return nil }
        let reverseName: String? = if case .linkingHere(let property) = draft.relation { BaseRollupDraft.reverseRelationName(property: property) } else { nil }
        return draft.sourceText(reverseFormulaName: reverseName)
    }

    private func saveDraft() {
        guard let draft else { return }
        isSaving = true
        failureMessage = nil
        Task {
            if let message = await save(draft) {
                failureMessage = message
                isSaving = false
            } else {
                dismiss()
            }
        }
    }
}
