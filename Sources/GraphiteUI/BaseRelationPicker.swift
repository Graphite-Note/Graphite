/**
 * File: BaseRelationPicker.swift
 * ------------------------------
 * Layer: UI
 * Description: Chooses the notes a relation property of a base's row links to: the linked notes, removable, and the
 *              notes the vault offers, found as they are typed.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import SwiftUI
import GraphiteCore

/// What the relation picker reads and writes for one row's property (`BaseDocumentModel`, `BaseNoteServices`).
struct BaseRelationEditing {
    /// Whether the property is a relation, so the sheet opens on the picker.
    let isRelation: @MainActor () async -> Bool
    /// The notes the property links to now, as the note writes them.
    let currentChoices: @MainActor () async -> [BaseRelationChoice]
    /// The notes the picker offers for the typed text.
    let candidates: @MainActor (_ query: String) async -> [BaseRelationCandidate]
    /// The link target naming a newly chosen note from the row's note, in the vault's link format, without brackets.
    let linkTarget: @MainActor (_ path: VaultPath) async -> String
    /// One link or a list.
    let shape: BaseRelationShape
}

/// The picker's state: the chosen notes, in order, and the notes offered for the query.
@MainActor @Observable
final class BaseRelationPickerState {
    private(set) var choices: [BaseRelationChoice] = []
    private(set) var candidates: [BaseRelationCandidate] = []
    private(set) var hasLoadedChoices = false
    /// The choices as loaded, so Save writes nothing when they did not change.
    private(set) var loadedChoices: [BaseRelationChoice] = []
    /// The query the shown candidates were found for; an answer for an older one is dropped.
    private var candidatesQuery: String?

    var hasChanges: Bool { choices != loadedChoices }
    var writtenItems: [String] { choices.map(\.writtenItem) }

    func loadChoices(_ editing: BaseRelationEditing) async {
        guard !hasLoadedChoices else { return }
        let loaded = await editing.currentChoices()
        choices = loaded
        loadedChoices = loaded
        hasLoadedChoices = true
    }

    func findCandidates(_ query: String, editing: BaseRelationEditing) async {
        candidatesQuery = query
        let found = await editing.candidates(query)
        guard candidatesQuery == query else { return }
        candidates = found
    }

    func isChosen(_ candidate: BaseRelationCandidate) -> Bool {
        choices.contains { choice in choice.path == candidate.path }
    }

    /// Chooses the note, or removes it when it is chosen. A single relation keeps only the newest choice.
    func toggle(_ candidate: BaseRelationCandidate, editing: BaseRelationEditing) async {
        if isChosen(candidate) {
            choices.removeAll { choice in choice.path == candidate.path }
            return
        }
        let target = await editing.linkTarget(candidate.path)
        let choice = BaseRelationChoice(writtenItem: BaseRelation.writtenItem(target: target), path: candidate.path)
        if editing.shape == .single { choices = [choice] } else { choices.append(choice) }
    }

    func remove(_ choice: BaseRelationChoice) {
        choices.removeAll { chosen in chosen.id == choice.id }
    }
}

/// The chosen notes with their remove buttons, a search field, and the offered notes with a checkmark on the chosen.
struct BaseRelationPicker: View {
    let editing: BaseRelationEditing
    @Bindable var state: BaseRelationPickerState
    @State private var query = ""

    var body: some View {
        Section {
            if state.choices.isEmpty {
                Text(state.hasLoadedChoices ? "No linked notes" : "Reading the note…").foregroundStyle(.secondary)
            }
            ForEach(state.choices) { choice in
                HStack(spacing: 8) {
                    Label(choice.title, systemImage: choice.path == nil ? "questionmark.square.dashed" : "doc.text")
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Button("Remove \(choice.title)", systemImage: "minus.circle.fill") { state.remove(choice) }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.red)
                        .buttonStyle(.borderless)
                }
            }
        } header: {
            Text(editing.shape == .single ? "Linked Note" : "Linked Notes")
        }
        Section {
            TextField("Search Notes", text: $query)
                .literalTextEntry()
            ForEach(state.candidates) { candidate in
                Button { Task { await state.toggle(candidate, editing: editing) } } label: {
                    candidateRow(candidate)
                }
                .buttonStyle(.borderless)
                .accessibilityAddTraits(state.isChosen(candidate) ? .isSelected : [])
            }
        } header: {
            Text("Notes")
        } footer: {
            Text("Notes this property already links to come first, then the other notes of their folders. Type to find any note.")
        }
        .task(id: query) { await state.findCandidates(query, editing: editing) }
        .task { await state.loadChoices(editing) }
    }

    private func candidateRow(_ candidate: BaseRelationCandidate) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.title).foregroundStyle(.primary).lineLimit(1)
                if !candidate.folder.isEmpty { Text(candidate.folder).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 8)
            if state.isChosen(candidate) { Image(systemName: "checkmark").foregroundStyle(.tint).accessibilityHidden(true) }
        }
        .contentShape(Rectangle())
    }
}
