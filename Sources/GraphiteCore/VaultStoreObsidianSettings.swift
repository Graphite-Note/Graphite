/**
 * File: VaultStoreObsidianSettings.swift
 * --------------------------------------
 * Layer: Core
 * Description: The vault's Obsidian settings files in `.obsidian`: `app.json`, property types, bookmarks, Templates,
 *              Daily notes and appearance, each read as Obsidian writes it and saved by merging only what changed.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 27/11/2026
 */

import Foundation

/// The vault's Obsidian settings files. Each save reads the file again and fails instead of overwriting when it changes
/// meanwhile, so a setting Obsidian changed since Graphite read it is kept.
extension VaultStore {
    static let applicationConfigurationPath = ".obsidian/app.json"
    private static let maximumConfigurationBytes = 1_048_576

    public func settings() throws -> ObsidianSettings {
        let path = try VaultPath(Self.applicationConfigurationPath)
        let settings = try fileExists(path)
            ? try ObsidianSettings(applicationConfigurationData: read(path, maximumBytes: Self.maximumConfigurationBytes).data)
            : ObsidianSettings()
        settingsBaseline = settings
        return settings
    }

    /// Property types assigned in Obsidian (`.obsidian/types.json`). Missing or unreadable
    /// files mean no assignments, and types are then inferred from values.
    public func propertyTypes() -> [String: PropertyType] {
        guard let path = try? VaultPath(Self.propertyTypesPath), (try? fileExists(path)) == true,
              let snapshot = try? read(path, maximumBytes: Self.maximumConfigurationBytes),
              let configuration = try? JSONSerialization.jsonObject(with: snapshot.data) as? [String: Any],
              let assignedTypes = configuration["types"] as? [String: String] else { return [:] }
        return assignedTypes.compactMapValues(PropertyType.init(rawValue:))
    }

    /// Assigns a type to a property in `.obsidian/types.json`, as Obsidian's Properties view
    /// does, keeping the rest of the file. The values in notes are not converted.
    public func setPropertyType(_ type: PropertyType, forKey key: String) throws {
        try updatePropertyTypeAssignments { assignments in
            let existingKey = assignments.keys.first { assignedKey in assignedKey.caseInsensitiveCompare(key) == .orderedSame } ?? key
            assignments[existingKey] = type.rawValue
        }
    }

    /// Moves a property's assigned type to its new name after a rename.
    public func movePropertyType(from oldKey: String, to newKey: String) throws {
        try updatePropertyTypeAssignments { assignments in
            guard let assignedKey = assignments.keys.first(where: { assignedKey in assignedKey.caseInsensitiveCompare(oldKey) == .orderedSame }),
                  let type = assignments.removeValue(forKey: assignedKey) else { return }
            assignments[newKey] = type
        }
    }

    private static var propertyTypesPath: String { ".obsidian/types.json" }

    /// Changes the property type assignments of `.obsidian/types.json` and keeps the rest of the file; unchanged
    /// assignments leave the file as it was.
    func updatePropertyTypeAssignments(_ update: (inout [String: Any]) -> Void) throws {
        try saveConfiguration(at: Self.propertyTypesPath) { existingData in
            var configuration: [String: Any] = [:]
            if let existingData, !existingData.isEmpty {
                guard let existing = try JSONSerialization.jsonObject(with: existingData) as? [String: Any] else {
                    throw GraphiteError.invalidFile("“.obsidian/types.json” is not a JSON object, so Graphite leaves it unchanged.")
                }
                configuration = existing
            }
            if let writtenAssignments = configuration["types"], !(writtenAssignments is NSNull), writtenAssignments as? [String: Any] == nil {
                throw GraphiteError.invalidFile("The property types in “.obsidian/types.json” are not a JSON object, so Graphite leaves them unchanged.")
            }
            var assignments = configuration["types"] as? [String: Any] ?? [:]
            let original = assignments as NSDictionary
            update(&assignments)
            // Unchanged assignments leave the file as it was, formatting included.
            if let existingData, original.isEqual(to: assignments) { return existingData }
            configuration["types"] = assignments
            return try JSONSerialization.data(withJSONObject: configuration, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        }
    }

    /// Obsidian's bookmarks (`.obsidian/bookmarks.json`); none when missing, an error when
    /// the file exists and cannot be read.
    public func bookmarks() throws -> BookmarkList {
        try BookmarkList(configurationData: configurationData(at: BookmarkList.configurationPath))
    }

    /// Applies `change` to the bookmarks as they are in the file now, so a change made
    /// elsewhere meanwhile is kept, and returns the result.
    @discardableResult
    public func updateBookmarks(_ change: (inout BookmarkList) -> Void) throws -> BookmarkList {
        var updated = BookmarkList()
        // A vault without bookmarks gets a file only once there is one to keep.
        if try configurationData(at: BookmarkList.configurationPath) == nil {
            change(&updated)
            if updated.items.isEmpty { return updated }
            updated = BookmarkList()
        }
        try saveConfiguration(at: BookmarkList.configurationPath) { existingData in
            let existing = try BookmarkList(configurationData: existingData)
            updated = existing
            change(&updated)
            // Unchanged bookmarks leave the file as it was, formatting included.
            if updated == existing, let existingData { return existingData }
            return try updated.configurationData()
        }
        return updated
    }

    /// Obsidian's Templates settings (`.obsidian/templates.json`); defaults when missing, an
    /// error when the file exists and cannot be read.
    public func templateSettings() throws -> TemplateSettings {
        try TemplateSettings(configurationData: configurationData(at: TemplateSettings.configurationPath))
    }

    public func saveTemplateSettings(_ settings: TemplateSettings) throws {
        try saveConfiguration(at: TemplateSettings.configurationPath) { existingData in try settings.mergedConfigurationData(existingData: existingData) }
    }

    /// Obsidian's Daily notes settings (`.obsidian/daily-notes.json`); defaults when missing,
    /// an error when the file exists and cannot be read.
    public func dailyNoteSettings() throws -> DailyNoteSettings {
        try DailyNoteSettings(configurationData: configurationData(at: DailyNoteSettings.configurationPath))
    }

    public func saveDailyNoteSettings(_ settings: DailyNoteSettings) throws {
        try saveConfiguration(at: DailyNoteSettings.configurationPath) { existingData in try settings.mergedConfigurationData(existingData: existingData) }
    }

    /// Obsidian's appearance settings (`.obsidian/appearance.json`); Obsidian's defaults
    /// when the file is missing. Throws when the file is there but is not a JSON object.
    public func appearance() throws -> ObsidianAppearance {
        let path = try VaultPath(ObsidianAppearance.configurationPath)
        let appearance = try fileExists(path)
            ? try ObsidianAppearance(configurationData: read(path, maximumBytes: Self.maximumConfigurationBytes).data)
            : ObsidianAppearance()
        appearanceBaseline = appearance
        return appearance
    }

    /// Writes the appearance settings that changed into `.obsidian/appearance.json`,
    /// keeping every other key and its layout. Fails instead of overwriting when the file
    /// changes during the merge.
    /// - Parameter previousAppearance: The settings the caller changed. Only keys that
    ///   differ from them are written, so a key Obsidian changed since keeps its new value.
    ///   Without them, the settings Graphite last read or saved are the starting point.
    public func saveAppearance(_ appearance: ObsidianAppearance, changedFrom previousAppearance: ObsidianAppearance? = nil) throws {
        let startingAppearance = previousAppearance ?? appearanceBaseline
        // Without a file, a save that changes nothing has nothing to write.
        if try !fileExists(VaultPath(ObsidianAppearance.configurationPath)), appearance == (startingAppearance ?? ObsidianAppearance()) {
            appearanceBaseline = appearance
            return
        }
        try saveConfiguration(at: ObsidianAppearance.configurationPath) { existingData in
            try appearance.mergedConfigurationData(existingData: existingData, changedFrom: startingAppearance)
        }
        appearanceBaseline = appearance
    }

    /// Internal so other Obsidian settings files in Core (community plugins) read the same way.
    /// Nil only when the file does not exist: a file that is too large or cannot be read
    /// throws, so a settings screen never shows an unreadable file as an empty one.
    func configurationData(at relativePath: String) throws -> Data? {
        let path = try VaultPath(relativePath)
        guard try fileExists(path) else { return nil }
        return try read(path, maximumBytes: Self.maximumConfigurationBytes).data
    }

    /// Rewrites an Obsidian settings file with `merge`, failing instead of overwriting
    /// when the file changes in the meantime.
    func saveConfiguration(at relativePath: String, merge: (Data?) throws -> Data) throws {
        let path = try VaultPath(relativePath)
        let url = try path.url(in: root)
        try createDirectory(path.parent)
        let existingSnapshot = try fileExists(path) ? try read(path, maximumBytes: Self.maximumConfigurationBytes) : nil
        let mergedConfiguration = try merge(existingSnapshot?.data)
        guard mergedConfiguration != existingSnapshot?.data else { return }
        try writer.write(mergedConfiguration, to: url, expecting: existingSnapshot.map { snapshot in .revision(snapshot.revision) } ?? .absent)
    }

    /// Writes the Graphite settings that changed into `.obsidian/app.json`, preserving
    /// everything else in the file. Fails instead of overwriting when the file changes
    /// during the merge.
    /// - Parameter previousSettings: The settings the caller changed, such as the copy a
    ///   settings screen shows. Only keys that differ from them are written, so a key
    ///   Obsidian changed since the caller's copy was read keeps its new value. Without
    ///   them, the settings Graphite last read or saved are the starting point.
    public func saveSettings(_ settings: ObsidianSettings, changedFrom previousSettings: ObsidianSettings? = nil) throws {
        let path = try VaultPath(Self.applicationConfigurationPath)
        let url = try path.url(in: root)
        let fileIsThere = try fileExists(path)
        let startingSettings = previousSettings ?? settingsBaseline
        // Without a file, a save that changes nothing has nothing to write.
        guard fileIsThere || settings != (startingSettings ?? ObsidianSettings()) else {
            settingsBaseline = settings
            return
        }
        try createDirectory(path.parent)
        let existingSnapshot = fileIsThere ? try writer.read(url, maximumBytes: Self.maximumConfigurationBytes) : nil
        let mergedConfiguration = try settings.mergedApplicationConfigurationData(existingData: existingSnapshot?.data, changedFrom: startingSettings)
        if mergedConfiguration != existingSnapshot?.data {
            try writer.write(mergedConfiguration, to: url, expecting: existingSnapshot.map { snapshot in .revision(snapshot.revision) } ?? .absent)
        }
        settingsBaseline = settings
    }
}
