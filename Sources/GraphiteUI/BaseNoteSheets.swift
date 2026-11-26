/**
 * File: BaseNoteSheets.swift
 * --------------------------
 * Layer: UI
 * Description: The sheets a base opens to make a note from a view, to set where New makes notes, and to add a
 *              rollup, and the relation picker's reads and writes for a property sheet.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import SwiftUI
import GraphiteCore

/// Which of a base's note sheets is open.
enum BaseNoteSheet: Identifiable {
    case newItem(BaseNewItemRequest)
    case newItemSettings
    case rollup(vaultPropertyNames: [String])

    var id: String {
        switch self {
        case .newItem(let request): "new-" + request.id.uuidString
        case .newItemSettings: "settings"
        case .rollup: "rollup"
        }
    }
}

/// Shows the sheet `sheet` names over a base, each saving through its model.
struct BaseNoteSheets: ViewModifier {
    let model: BaseDocumentModel
    let services: BaseNoteServices?
    @Binding var sheet: BaseNoteSheet?
    @Environment(\.accent) private var accent

    func body(content: Content) -> some View {
        content.sheet(item: $sheet) { shownSheet in
            sheetContent(shownSheet).tint(accent)
        }
    }

    @ViewBuilder private func sheetContent(_ shownSheet: BaseNoteSheet) -> some View {
        let model = model
        switch shownSheet {
        case .newItem(let request):
            BaseNewItemSheet(request: request, viewName: model.selectedView?.name ?? "Base") { name, groupKey in
                guard let services else { return "This base cannot make notes here." }
                guard await model.createNewItem(named: name, inGroup: groupKey, services: services) != nil else {
                    return model.takeActionErrorMessage(otherwise: "The note was not made.")
                }
                return nil
            }
        case .newItemSettings:
            BaseNewItemSettingsSheet(folder: model.definition?.newItemFolder ?? "", template: model.definition?.newItemTemplate ?? "") { folder, template in
                await model.setNewItemSettings(folder: folder, template: template) ? nil : model.takeActionErrorMessage(otherwise: "The base was not saved.")
            }
        case .rollup(let vaultPropertyNames):
            BaseRollupBuilderSheet(vaultPropertyNames: vaultPropertyNames, rowPropertyNames: model.availablePropertyKeys,
                                   noteFormulaNames: model.noteListFormulaNames) { draft in
                await model.addRollup(draft) ? nil : model.takeActionErrorMessage(otherwise: "The base was not saved.")
            }
        }
    }
}

extension BaseDocumentModel {
    /// The model's message for a failed save, moved into the open sheet so it is not also shown behind it.
    func takeActionErrorMessage(otherwise fallbackMessage: String) -> String {
        let message = actionErrorMessage ?? fallbackMessage
        actionErrorMessage = nil
        return message
    }

    /// The relation picker's reads and writes for one row's property, through the vault's services.
    /// Nil without the vault's services, which offers no picker.
    func relationEditing(for request: BaseEditRequest, writtenNode: BaseFrontmatterNode?, services: BaseNoteServices?) -> BaseRelationEditing? {
        guard let services else { return nil }
        let path = request.path
        let property = request.property
        let value = request.currentValue
        return BaseRelationEditing(
            isRelation: { [weak self] in await self?.isRelation(property, value: value) ?? false },
            currentChoices: { [weak self] in await self?.relationChoices(of: path, value: value, writtenNode: writtenNode) ?? [] },
            candidates: { [weak self] query in await self?.relationCandidates(for: property, of: path, query: query, services: services) ?? [] },
            linkTarget: { notePath in await services.linkTarget(notePath, path) },
            shape: relationShape(property, value: value))
    }

    /// The vault's property names, for the rollup builder: the vault's names when known, else this base's.
    func rollupPropertyNames(services: BaseNoteServices?) async -> [String] {
        let vaultNames = await services?.vaultPropertyTypes().keys.map { name in name } ?? []
        let names = vaultNames.isEmpty ? availablePropertyKeys : vaultNames
        return names.sorted { leftName, rightName in leftName.localizedStandardCompare(rightName) == .orderedAscending }
    }
}

/// The toolbar's entries for making notes and rollups (`Docs/Bases-relations-todo.md`): each opens its sheet.
struct BaseToolbarNoteActions {
    let newItem: () -> Void
    let addRollup: () -> Void
    let editNewItemSettings: () -> Void

    /// Nil while the vault cannot link and make notes here.
    @MainActor init?(model: BaseDocumentModel, services: BaseNoteServices?, sheet: Binding<BaseNoteSheet?>) {
        guard model.canCreateNewItem(services: services) else { return nil }
        newItem = { sheet.wrappedValue = .newItem(BaseNewItemRequest(groupKey: nil, groupTitle: nil)) }
        addRollup = { Task { sheet.wrappedValue = .rollup(vaultPropertyNames: await model.rollupPropertyNames(services: services)) } }
        editNewItemSettings = { sheet.wrappedValue = .newItemSettings }
    }
}

/// New in the base's toolbar row: no row of its own.
struct BaseNewItemButton: View {
    let actions: BaseToolbarNoteActions

    var body: some View {
        Button("New", systemImage: "plus", action: actions.newItem)
            .labelStyle(.iconOnly)
            .help("New note in this view")
    }
}

/// The view menu's entries for rollups, New's settings and the embed of the view.
struct BaseNoteMenuEntries: View {
    let model: BaseDocumentModel
    let actions: BaseToolbarNoteActions?

    var body: some View {
        if let actions {
            Button("Add Rollup…", systemImage: "function", action: actions.addRollup)
            Button("New Note Settings…", systemImage: "doc.badge.gearshape", action: actions.editNewItemSettings)
        }
        if case .file(let basePath) = model.source {
            // Pasted into a note, it shows this view there, with that note as `this`.
            Button("Copy Embed Link", systemImage: "link") { Pasteboard.copy(BaseEmbedLink.text(basePath: basePath, viewName: model.selectedView?.name)) }
        }
    }
}
