/**
 * File: CalendarSettings.swift
 * ----------------------------
 * Layer: Core
 * Description: The Calendar core plugin's settings of a vault, kept in `.obsidian/graphite-calendar.json`: where each
 *              calendar's event notes go, and the Reminders lists tasks are sent to and brought in from.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

import Foundation

/// The Calendar core plugin's settings of a vault, in `.obsidian/graphite-calendar.json`, which Obsidian ignores.
/// Calendars and lists are named by their titles, which are the same on every device of the person, where EventKit's
/// identifiers are not. Keys this build does not know are kept when the file is written.
public struct CalendarSettings: Equatable, Sendable {
    public static let configurationPath = ".obsidian/graphite-calendar.json"

    /// The folder of each calendar's event notes, by the calendar's title.
    public var eventNoteFolders: [String: String]
    /// The folder of event notes whose calendar has none of its own; empty for the vault's default location for new notes.
    public var defaultEventNoteFolder: String
    /// The Reminders list tasks are sent to; empty for the list Reminders adds new reminders to.
    public var taskListTitle: String
    /// The Reminders list brought into notes; empty for every list.
    public var importedListTitle: String

    public init(eventNoteFolders: [String: String] = [:], defaultEventNoteFolder: String = "", taskListTitle: String = "", importedListTitle: String = "") {
        self.eventNoteFolders = eventNoteFolders
        self.defaultEventNoteFolder = defaultEventNoteFolder
        self.taskListTitle = taskListTitle
        self.importedListTitle = importedListTitle
    }

    /// Reads the file; a missing file, a missing key or a value of another type takes the default.
    public init(configurationData: Data?) {
        // A file that is not JSON reads as the defaults, and is never written over (`mergedConfigurationData`).
        let decoded = configurationData.flatMap { data in try? JSONDecoder().decode(JSONValue.self, from: data) } // Not JSON: the defaults.
        guard case .object(let fields) = decoded else {
            self.init()
            return
        }
        func text(_ key: String) -> String {
            if case .string(let text) = fields[key] { return text }
            return ""
        }
        var folders: [String: String] = [:]
        if case .object(let folderFields) = fields["eventNoteFolders"] {
            for (calendarTitle, folderValue) in folderFields {
                guard case .string(let folder) = folderValue else { continue }
                let trimmedFolder = PluginConfiguration.folder(folder)
                if !trimmedFolder.isEmpty { folders[calendarTitle] = trimmedFolder }
            }
        }
        self.init(eventNoteFolders: folders, defaultEventNoteFolder: PluginConfiguration.folder(text("defaultEventNoteFolder")),
                  taskListTitle: text("taskList"), importedListTitle: text("importedList"))
    }

    /// The file with these settings, keeping any other keys it has; throws for a file that is not a JSON object, which
    /// is then left as it is.
    public func mergedConfigurationData(existingData: Data?) throws -> Data {
        try PluginConfiguration.merged(existingData: existingData, values: [
            "eventNoteFolders": eventNoteFolders, "defaultEventNoteFolder": defaultEventNoteFolder,
            "taskList": taskListTitle, "importedList": importedListTitle,
        ])
    }

    /// The folder for a note of an event of `calendarTitle`: the calendar's own, else the default; nil when neither is
    /// set, for the vault's default location for new notes.
    public func eventNoteFolder(forCalendarTitled calendarTitle: String) -> VaultPath? {
        let folder = eventNoteFolders[calendarTitle].flatMap { folder in folder.isEmpty ? nil : folder } ?? defaultEventNoteFolder
        return folder.isEmpty ? nil : try? VaultPath(folder) // A folder no path can name: the vault's location for new notes.
    }
}

extension VaultStore {
    /// The Calendar core plugin's settings (`.obsidian/graphite-calendar.json`); defaults when the file is missing.
    public func calendarSettings() throws -> CalendarSettings {
        try CalendarSettings(configurationData: configurationData(at: CalendarSettings.configurationPath))
    }

    public func saveCalendarSettings(_ settings: CalendarSettings) throws {
        try saveConfiguration(at: CalendarSettings.configurationPath) { existingData in try settings.mergedConfigurationData(existingData: existingData) }
    }
}
