/**
 * File: NotionImportWording.swift
 * -------------------------------
 * Layer: UI
 * Description: The words of Import from Notion: how to export from Notion, the progress, and the summary of an import.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import Foundation
import GraphiteCore

/// The words Import from Notion shows, kept apart from its views so that tests read them.
enum NotionImportWording {
    static let exportSteps = """
        In Notion's Settings, choose Export all workspace content (or Export in a page's ••• menu), with the format HTML \
        and Include subpages on. Notion gives a .zip file, or several Part zips for a large workspace: choose them all.
        """

    static let whatIsImported = """
        Pages become notes, databases become bases with their rows as notes, and attachments are copied beside them. \
        Nothing already in the vault is changed, and a report note lists what was simplified or left out.
        """

    /// Where the export goes, as the sheet says it: "Courses/Notion", or "Notion" in the vault's own folder.
    static func destinationDescription(of directory: VaultPath) -> String {
        let folder = "A new folder “\(NotionImportRun.folderName)”"
        return directory.rawValue.isEmpty ? folder : "\(folder) in “\(directory.rawValue)”"
    }

    static func progressTitle(isPaused: Bool, isCancelling: Bool) -> String {
        if isCancelling { return "Stopping the Notion Import…" }
        return isPaused ? "Notion Import Paused" : "Importing from Notion"
    }

    static func progressDetail(_ progress: NotionImportProgress) -> String {
        guard progress.pageCount > 0 else { return "Reading the export…" }
        return "\(progress.finishedPageCount.formatted()) of \(progress.pageCount.formatted()) pages"
    }

    static func title(of summary: NotionImportSummary) -> String {
        if summary.failureMessage != nil { return "Notion Import Failed" }
        return summary.wasCancelled ? "Notion Import Stopped" : "Notion Import Finished"
    }

    static func headline(of summary: NotionImportSummary) -> String {
        if let failureMessage = summary.failureMessage { return failureMessage }
        let written = [counted(summary.noteCount, "note", "notes"), counted(summary.baseCount, "base", "bases"),
                       counted(summary.attachmentCount, "attachment", "attachments")].compactMap { phrase in phrase }
        let folder = summary.folder.map { folder in " into “\(folder.rawValue)”" } ?? ""
        guard !written.isEmpty else { return "Nothing was imported\(folder)." }
        return "Imported \(ListFormatter.localizedString(byJoining: written))\(folder)."
    }

    static func details(of summary: NotionImportSummary) -> [String] {
        guard summary.failureMessage == nil else { return [] }
        var details: [String] = []
        if summary.wasCancelled { details.append("The import was stopped: what it wrote before stays, and the report says what was not imported.") }
        if summary.findingCount > 0 {
            details.append(summary.findingCount == 1 ? "The report lists 1 thing that was simplified or left out."
                : "The report lists \(summary.findingCount.formatted()) things that were simplified or left out.")
        }
        return details
    }

    private static func counted(_ count: Int, _ singular: String, _ plural: String) -> String? {
        guard count > 0 else { return nil }
        return count == 1 ? "1 \(singular)" : "\(count.formatted()) \(plural)"
    }
}
