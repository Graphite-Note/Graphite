/**
 * File: WorkspaceBaseNoteServices.swift
 * -------------------------------------
 * Layer: UI
 * Description: The open vault's services for bases that link notes and make new ones: link format, search, templates,
 *              property types and opening a new note.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import Foundation
import GraphiteCore

extension WorkspaceModel {
    /// What bases need to link and make notes in the open vault; nil when Bases are off or no vault is open.
    var baseNoteServices: BaseNoteServices? {
        guard preferences.isEnabled(.bases), index != nil, store != nil else { return nil }
        let suggestions = propertySuggestions
        return BaseNoteServices(
            linkTarget: { [weak self] path, note in
                guard let self else { return path.stem }
                return LinkCompletion.linkTarget(for: path, from: note, settings: self.vaultSettings, isNameUnique: await self.isNameUnique(path, from: note))
            },
            searchNotes: { [weak self] query, limit in
                guard let index = self?.index else { return [] }
                let matches = (try? await index.quickSwitcherMatches(for: query, limit: limit, onlyFileExtensions: ["md"])) ?? [] // No answer, no notes.
                return matches.map(\.path)
            },
            fillTemplate: { [weak self] templateText, title in
                guard let self else { return templateText }
                let settings = self.templateSettings
                return TemplateRenderer.render(templateText, title: title, date: .now, dateFormat: settings.dateFormat, timeFormat: settings.timeFormat,
                                               language: self.preferences.dateNames.language)
            },
            newNoteLocation: vaultSettings.newNoteLocation,
            vaultPropertyTypes: {
                let summaries = await suggestions.vaultNames()
                return Dictionary(summaries.map { summary in (summary.key, summary.type) }, uniquingKeysWith: { first, _ in first })
            },
            showNewNote: { [weak self] path in
                guard let self else { return }
                self.refreshIndex(for: [path])
                Task {
                    await self.open(path, placement: .newTab)
                    await self.showInListings(path)
                }
            })
    }
}
