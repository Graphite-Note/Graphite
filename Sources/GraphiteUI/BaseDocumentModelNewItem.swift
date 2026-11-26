/**
 * File: BaseDocumentModelNewItem.swift
 * ------------------------------------
 * Layer: UI
 * Description: New in a base view: makes a note in the base's folder with the values the view's filters imply and the
 *              body of the base's template, and opens it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import Foundation
import GraphiteCore
import GraphiteIndex

extension BaseDocumentModel {
    /// Templates are small notes; a larger file is not read as one.
    private static let maximumTemplateBytes = 1_048_576

    /// Makes the note New in the selected view makes (`Docs/Bases-relations-todo.md`, section 3): named `name` (made
    /// unique in its folder), in the folder and with the properties `BaseNewItemPlanner` and `BaseNewItemNote` decide,
    /// and in a Kanban column with that column's value. Reports a failure in `actionErrorMessage`.
    /// - Parameter groupKey: The Kanban column the note is made in, nil for New in the toolbar.
    /// - Returns: The new note, or nil when none was made.
    @discardableResult
    func createNewItem(named name: String, inGroup groupKey: BaseCellValue? = nil, services: BaseNoteServices) async -> VaultPath? {
        guard let definition, let view = selectedView else { return nil }
        do {
            let request = try await newItemRequest(definition: definition, view: view, groupKey: groupKey, services: services)
            let path = try await store.uniquePath(directory: request.folder, stem: Self.noteStem(name), extension: "md")
            var linkTexts: [VaultPath: String] = [:]
            for linkedPath in request.plan.linkedPaths where linkTexts[linkedPath] == nil {
                linkTexts[linkedPath] = await services.linkTarget(linkedPath, path)
            }
            let namedLinks = linkTexts
            let filledTemplate = request.templateText.map { text in services.fillTemplate(text, path.stem) }
            let declaredTypes = declaredTypes
            let calendar = BaseDateFormatting.displayCalendar
            let plan = request.plan
            let groupProperty = request.groupProperty
            let noteText = try await Task.detached(priority: .userInitiated) {
                let linkText: (VaultPath) -> String = { linked in namedLinks[linked] ?? linked.stem }
                var properties = plan.properties.map { property in
                    NoteProperty(key: property.name, value: BaseNewItemNote.propertyValue(property.value, linkText: linkText, calendar: calendar))
                }
                if let groupProperty {
                    properties.removeAll { property in property.key.caseInsensitiveCompare(groupProperty.key) == .orderedSame }
                    properties.append(groupProperty)
                }
                return try BaseNewItemNote.text(template: filledTemplate, properties: properties, declaredTypes: declaredTypes)
            }.value
            try await store.createDirectory(path.parent)
            _ = try await store.save(Data(noteText.utf8), at: path, expecting: .absent)
            services.showNewNote(path)
            return path
        } catch {
            actionErrorMessage.report(error)
            return nil
        }
    }

    /// Whether New can make a note here: a view is shown and the vault offers the services New needs.
    func canCreateNewItem(services: BaseNoteServices?) -> Bool {
        services != nil && selectedView != nil && definition != nil
    }

    /// A name as a file's stem: the typed name without characters a file name cannot hold, "Untitled" when empty.
    nonisolated static func noteStem(_ name: String) -> String {
        let cleaned = name.components(separatedBy: CharacterSet(charactersIn: "/\\:")).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let stem = cleaned.hasSuffix(".md") ? String(cleaned.dropLast(3)) : cleaned
        return stem.isEmpty ? BaseNewItemNote.untitledName : stem
    }

    /// What the note New makes needs before it is named: the plan, the folder, the template and a column's value.
    private struct NewItemRequest: Sendable {
        let plan: BaseNewItemPlan
        let folder: VaultPath
        let templateText: String?
        let groupProperty: NoteProperty?
    }

    private func newItemRequest(definition: BaseDefinition, view: BaseView, groupKey: BaseCellValue?,
                                services: BaseNoteServices) async throws -> NewItemRequest {
        let templatePath = try await newItemTemplatePath(definition)
        var templateText: String?
        if let templatePath { templateText = try await readTemplate(templatePath) }
        let vaultTypes = await services.vaultPropertyTypes()
        let declaredTypes = declaredTypes
        let listNames = Set(vaultTypes.merging(declaredTypes) { _, declared in declared }.filter { entry in BaseNoteServices.isList(entry.value) }
            .map { entry in entry.key.lowercased() })
        let contextPath = contextPath
        let index = index
        let provider = index.baseRecordProvider
        let viewIndex = selectedViewIndex
        let environment = BaseEvaluationEnvironment(now: .now, calendar: BaseDateFormatting.displayCalendar, declaredTypes: declaredTypes)
        let provisionalFolder = BaseNewItemNote.folder(newItemFolder: definition.newItemFolder, filterFolder: nil, templatePath: nil,
                                                       newNoteLocation: services.newNoteLocation, currentFile: contextPath)
        // Detached: the evaluator's lookups read the index's database synchronously.
        let plan = try await Task.detached(priority: .userInitiated) { () throws -> BaseNewItemPlan in
            let thisRecord = try await index.baseRecord(at: contextPath) ?? BaseFileRecord(path: contextPath, size: 0, createdDate: environment.now,
                                                                                            modifiedDate: environment.now)
            let newNote = BaseFileRecord(path: try provisionalFolder.appending(BaseNewItemNote.untitledName + ".md"), size: 0,
                                         createdDate: environment.now, modifiedDate: environment.now)
            let evaluator = BaseEvaluator(formulas: definition.formulas, environment: environment, thisRecord: thisRecord, knownRecords: [newNote],
                                          provider: provider)
            let plan = BaseNewItemPlanner.plan(definition: definition, viewIndex: viewIndex, evaluator: evaluator, newNote: newNote,
                                               isListProperty: { name in listNames.contains(name.lowercased()) })
            try provider.throwIfLookupFailed()
            return plan
        }.value
        let folder = BaseNewItemNote.folder(newItemFolder: definition.newItemFolder, filterFolder: plan.filterFolder, templatePath: templatePath,
                                            newNoteLocation: services.newNoteLocation, currentFile: contextPath)
        let column = Self.column(groupKey, groupedBy: view.groupBy)
        return NewItemRequest(plan: plan, folder: column.folder ?? folder, templateText: templateText, groupProperty: column.property)
    }

    /// What a Kanban column gives its new note, as Obsidian's New in a column: the grouped property's value, or for a
    /// board grouped by folder, the column's folder.
    private nonisolated static func column(_ groupKey: BaseCellValue?, groupedBy groupBy: BaseSortKey?) -> (property: NoteProperty?, folder: VaultPath?) {
        guard let groupKey, let groupBy else { return (nil, nil) }
        switch groupBy.property {
        case .note(let name):
            return (propertyValue(forGroupKey: groupKey).map { value in NoteProperty(key: name, value: value) }, nil)
        case .file("folder"):
            guard case .value(.string(let folderText)) = groupKey else { return (nil, nil) }
            return (nil, try? VaultPath(folderText)) // A key no folder path can be: the base's folder.
        case .file, .formula:
            return (nil, nil)
        }
    }

    /// The template the base names, as Obsidian finds it by its vault path; a path without `.md` is tried with it.
    private func newItemTemplatePath(_ definition: BaseDefinition) async throws -> VaultPath? {
        guard let written = definition.newItemTemplate else { return nil }
        let normalized = BaseEvaluator.normalizedFolderPath(written)
        let candidates = [normalized, normalized + ".md"].compactMap { text in try? VaultPath(text) } // A path no file can have: not the template.
        for candidate in candidates where try await store.fileExists(candidate) { return candidate }
        throw BaseNewItemError.missingTemplate(written)
    }

    private func readTemplate(_ path: VaultPath) async throws -> String {
        let snapshot = try await store.read(path, maximumBytes: Self.maximumTemplateBytes)
        guard let text = UTF8FileText(snapshot.data)?.text else { throw BaseNewItemError.templateIsNotText(path.rawValue) }
        return text
    }
}
