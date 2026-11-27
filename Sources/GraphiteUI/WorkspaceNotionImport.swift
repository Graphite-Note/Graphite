/**
 * File: WorkspaceNotionImport.swift
 * ---------------------------------
 * Layer: UI
 * Description: Opens Import from Notion's sheet and hands the chosen export to a Notion import session.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import Foundation
import GraphiteCore

/// The sheet of Import from Notion, for one vault folder.
struct NotionImportChoice: Identifiable, Equatable {
    let id = UUID()
    /// The folder the export goes into, in a new folder "Notion".
    let directory: VaultPath
}

/// Importing Notion's HTML export: the New menu's Import from Notion, the sidebar's, and the Mac's File menu open its
/// sheet (`chooseNotionExport`), whose chosen export reaches `importNotionExport`.
extension WorkspaceModel {
    /// Shows Import from Notion's sheet for `directory` (the vault's folder for new files when nil), while the Notion
    /// Import core plugin is on.
    func chooseNotionExport(into directory: VaultPath?) {
        guard preferences.isEnabled(.notionImport), store != nil else { return }
        notionImportChoice = NotionImportChoice(directory: newFileDirectory(directory))
    }

    /// Import from Notion's action for a menu, for the vault's folder for new files; nil while its core plugin is off.
    var notionImportOpener: (@MainActor () -> Void)? {
        guard preferences.isEnabled(.notionImport) else { return nil }
        return { [weak self] in self?.chooseNotionExport(into: nil) }
    }

    /// Imports the export of `sources` into `directory`, away from the main actor, while the vault stays usable; the
    /// progress shows over the document area and a summary follows (`NotionImportPresentation`). One import runs at a
    /// time: while one runs, the person is told to wait.
    /// - Returns: Whether the import started.
    @discardableResult
    func importNotionExport(_ sources: [URL], into directory: VaultPath) -> Bool {
        guard let store, !sources.isEmpty else { return false }
        guard notionImport == nil else {
            errorMessage = "A Notion export is already being imported. Import this one when that import has finished."
            return false
        }
        // The one read of the wall clock for an import: its report is dated the day it began.
        let run = NotionImportRun(store: store, pause: NotionImportPause(), filesDidChange: { [weak self] paths in
            self?.refreshIndex(for: paths)
            await self?.refreshDirectory()
        }, importDate: WallClock.currentDate(), calendar: BaseDateFormatting.displayCalendar)
        notionImport = NotionImportSession(sources: sources, directory: directory, run: run)
        return true
    }

    /// Lets the import go once its summary is closed, so nothing of it stays.
    func endNotionImport() {
        notionImport?.stopImportAndObservation()
        notionImport = nil
    }
}
