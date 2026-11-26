/**
 * File: BaseNewItemSheet.swift
 * ----------------------------
 * Layer: UI
 * Description: Names the note New in a base view makes, and edits where New makes notes and which template it starts
 *              from.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import SwiftUI
import GraphiteCore

/// Where New was asked for: the base's toolbar, or a Kanban column.
struct BaseNewItemRequest: Identifiable {
    let id = UUID()
    /// The column's value, which the note takes; nil from the toolbar.
    let groupKey: BaseCellValue?
    /// The column's title, shown in the sheet.
    let groupTitle: String?
}

/// Names the note New makes, prefilled with "Untitled", and makes it on Create. Stays open with the reason when the
/// note cannot be made.
struct BaseNewItemSheet: View {
    let request: BaseNewItemRequest
    let viewName: String
    /// Makes the note and returns nil, or returns why it was not made.
    let create: (_ name: String, _ groupKey: BaseCellValue?) async -> String?
    @Environment(\.dismiss) private var dismiss
    @State private var name = BaseNewItemNote.untitledName
    @State private var isCreating = false
    @State private var failureMessage: String?
    @FocusState private var isNameFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .focused($isNameFocused)
                        .onSubmit(createNote)
                } footer: {
                    Text(footerText)
                }
                if let failureMessage {
                    Section { Label(failureMessage, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Note")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Create", action: createNote).disabled(isCreating) }
            }
        }
        #if os(macOS)
        .frame(minWidth: 340, minHeight: 200)
        #endif
        .interactiveDismissDisabled(isCreating)
        .onAppear { isNameFocused = true }
    }

    private var footerText: String {
        let place = request.groupTitle.map { title in "the column “\(title)” of “\(viewName)”" } ?? "“\(viewName)”"
        return "The note gets the properties \(place) shows, and opens in a new tab."
    }

    private func createNote() {
        guard !isCreating else { return }
        isCreating = true
        failureMessage = nil
        Task {
            if let message = await create(name, request.groupKey) {
                failureMessage = message
                isCreating = false
            } else {
                dismiss()
            }
        }
    }
}

/// Edits `newItemFolder` and `newItemTemplate`, the keys of a `.base` file Obsidian's New reads.
struct BaseNewItemSettingsSheet: View {
    let folder: String
    let template: String
    /// Saves the two values and returns nil, or returns why the base was not saved.
    let save: (_ folder: String, _ template: String) async -> String?
    @Environment(\.dismiss) private var dismiss
    @State private var editedFolder = ""
    @State private var editedTemplate = ""
    @State private var isSaving = false
    @State private var failureMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Folder", text: $editedFolder, prompt: Text("From the view's filters"))
                        .literalTextEntry()
                } header: {
                    Text("New Item Folder")
                } footer: {
                    Text("Where New makes its notes, as a path from the vault's folder. "
                         + "Empty uses the folder the view's filters name, then the vault's location for new notes.")
                }
                Section {
                    TextField("Template", text: $editedTemplate, prompt: Text("None"))
                        .literalTextEntry()
                } header: {
                    Text("New Item Template File")
                } footer: {
                    Text("A note whose properties and text each new note starts from, as a path such as Templates/Assignment.md.")
                }
                if let failureMessage {
                    Section { Label(failureMessage, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Note Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: saveSettings).disabled(isSaving) }
            }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 320)
        #endif
        .interactiveDismissDisabled(isSaving)
        .onAppear {
            editedFolder = folder
            editedTemplate = template
        }
    }

    private func saveSettings() {
        guard editedFolder != folder || editedTemplate != template else { dismiss(); return }
        isSaving = true
        failureMessage = nil
        Task {
            if let message = await save(editedFolder, editedTemplate) {
                failureMessage = message
                isSaving = false
            } else {
                dismiss()
            }
        }
    }
}
