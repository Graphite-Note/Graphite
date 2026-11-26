/**
 * File: CalendarCopySettings.swift
 * --------------------------------
 * Layer: Core
 * Description: Which base and calendar view the Calendar Copy core plugin copies into Apple Calendar, kept for the
 *              vault under `copiedBase` in `.obsidian/graphite-calendar.json`.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import Foundation

/// The base and calendar view Calendar Copy copies, the vault's choice, so every device of the person copies the same
/// notes. It sits beside the Calendar plugin's settings (`CalendarSettings`), whose keys it never writes.
public struct CalendarCopySettings: Equatable, Sendable {
    public static let key = "copiedBase"

    /// The `.base` file, nil until one is chosen.
    public var basePath: VaultPath?
    /// The name of its calendar view.
    public var viewName: String

    public init(basePath: VaultPath? = nil, viewName: String = "") {
        self.basePath = basePath
        self.viewName = viewName
    }

    /// Whether a base and a view are chosen.
    public var isChosen: Bool { basePath != nil && !viewName.isEmpty }

    /// Reads `copiedBase` (`{"file": "Courses/Deadlines.base", "view": "Calendar"}`); anything else reads as nothing chosen.
    public init(configurationData: Data?) {
        let decoded = configurationData.flatMap { data in try? JSONDecoder().decode(JSONValue.self, from: data) } // Not JSON: nothing chosen.
        guard case .object(let fields) = decoded, case .object(let chosen)? = fields[Self.key] else {
            self.init()
            return
        }
        func text(_ name: String) -> String {
            if case .string(let text) = chosen[name] { return text }
            return ""
        }
        let file = text("file")
        self.init(basePath: file.isEmpty ? nil : try? VaultPath(file), viewName: text("view")) // A path no vault can hold: nothing chosen.
    }

    /// The file with this choice, keeping every other key; throws for a file that is not a JSON object.
    public func mergedConfigurationData(existingData: Data?) throws -> Data {
        try PluginConfiguration.merged(existingData: existingData, values: [Self.key: ["file": basePath?.rawValue ?? "", "view": viewName]])
    }
}

extension VaultStore {
    public func calendarCopySettings() throws -> CalendarCopySettings {
        try CalendarCopySettings(configurationData: configurationData(at: CalendarSettings.configurationPath))
    }

    public func saveCalendarCopySettings(_ settings: CalendarCopySettings) throws {
        try saveConfiguration(at: CalendarSettings.configurationPath) { existingData in try settings.mergedConfigurationData(existingData: existingData) }
    }
}
