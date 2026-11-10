/**
 * File: CommunityPluginList.swift
 * -------------------------------
 * Layer: Core
 * Description: The community plugins Graphite runs: its own list, apart from Obsidian's, and the plugins it does itself.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 10/11/2026
 */

import Foundation

/// A list of enabled community plugins in Obsidian's format: a JSON array of plugin
/// identifiers, in the order they were turned on. Obsidian keeps its own in
/// `.obsidian/community-plugins.json`; Graphite keeps a separate one in
/// `.graphite/community-plugins.json`, so a plugin turned on in one app is not turned on in
/// the other. A vault where Graphite has not switched a plugin yet has no Graphite list,
/// and Graphite follows Obsidian's, without the plugins it does itself.
public struct CommunityPluginList: Equatable, Sendable {
    public static let obsidianConfigurationPath = ".obsidian/community-plugins.json"
    public static let graphiteConfigurationPath = ".graphite/community-plugins.json"
    public static let pluginsFolderPath = ".obsidian/plugins"

    /// Plugins whose work Graphite does itself, or which act only through Obsidian's editor
    /// (CodeMirror extensions, which Graphite's editor does not run), with what does their
    /// work in Graphite. While Graphite follows Obsidian's list they stay off in Graphite,
    /// as each would cost memory and do nothing; switching one on in Graphite runs it.
    public static let pluginsGraphiteDoesItself: [String: String] = [
        "omnisearch": "Graphite's own search finds notes by their words.",
        "maps": "Graphite draws map views of bases itself.",
        "colors": "Graphite's Colors core plugin shows and writes the same colored text.",
        "obsidian-latex-suite": "Its snippets and shortcuts work through Obsidian's editor, which Graphite's editor does not run.",
    ]

    public private(set) var enabledIdentifiers: [String]

    public init(enabledIdentifiers: [String] = []) {
        self.enabledIdentifiers = enabledIdentifiers
    }

    /// Reads the file's bytes; a missing or empty file means no plugin is on. Entries that
    /// are not text are left out, as Obsidian ignores them.
    /// - Parameter configurationPath: The file the bytes came from, for the error.
    public init(configurationData: Data?, configurationPath: String = Self.obsidianConfigurationPath) throws {
        guard let configurationData, !configurationData.allSatisfy({ byte in byte == 0x20 || byte == 0x0A || byte == 0x0D || byte == 0x09 }) else {
            self.init()
            return
        }
        guard let entries = try? JSONSerialization.jsonObject(with: configurationData) as? [Any] else {
            throw GraphiteError.invalidFile("“\(configurationPath)” is not a list of plugins, so Graphite leaves it unchanged.")
        }
        self.init(enabledIdentifiers: entries.compactMap { entry in entry as? String })
    }

    public func isEnabled(_ identifier: String) -> Bool { enabledIdentifiers.contains(identifier) }

    /// Obsidian's list as Graphite runs it while it has no list of its own: without the
    /// plugins Graphite does itself.
    public var withoutPluginsGraphiteDoesItself: CommunityPluginList {
        CommunityPluginList(enabledIdentifiers: enabledIdentifiers.filter { identifier in Self.pluginsGraphiteDoesItself[identifier] == nil })
    }

    /// Turns a plugin on (added at the end, as Obsidian adds it) or off.
    public mutating func setEnabled(_ identifier: String, _ isEnabled: Bool) {
        if isEnabled {
            if !enabledIdentifiers.contains(identifier) { enabledIdentifiers.append(identifier) }
        } else {
            enabledIdentifiers.removeAll { enabledIdentifier in enabledIdentifier == identifier }
        }
    }

    /// The file as Obsidian writes it: `JSON.stringify(list, null, 2)`.
    public func configurationData() throws -> Data {
        guard !enabledIdentifiers.isEmpty else { return Data("[]".utf8) }
        let entries = try enabledIdentifiers.map { identifier -> String in
            let literal = try JSONSerialization.data(withJSONObject: identifier, options: [.fragmentsAllowed, .withoutEscapingSlashes])
            return "  " + String(decoding: literal, as: UTF8.self)
        }
        return Data(("[\n" + entries.joined(separator: ",\n") + "\n]").utf8)
    }
}

public extension VaultStore {
    /// The community plugins Graphite runs: Graphite's own list, or, while Graphite has
    /// none, Obsidian's without the plugins Graphite does itself. None when neither file
    /// exists.
    func communityPluginList() throws -> CommunityPluginList {
        if let graphiteData = try configurationData(at: CommunityPluginList.graphiteConfigurationPath) {
            return try CommunityPluginList(configurationData: graphiteData, configurationPath: CommunityPluginList.graphiteConfigurationPath)
        }
        return try obsidianListAsGraphiteRunsIt()
    }

    private func obsidianListAsGraphiteRunsIt() throws -> CommunityPluginList {
        try CommunityPluginList(configurationData: configurationData(at: CommunityPluginList.obsidianConfigurationPath)).withoutPluginsGraphiteDoesItself
    }

    /// Applies `change` to Graphite's list as it is in its file now, and returns the
    /// result. Obsidian's list is never written: the first change starts Graphite's file
    /// from Obsidian's list as Graphite runs it then (`communityPluginList()`), and from
    /// then on the two are separate.
    @discardableResult
    func updateCommunityPluginList(_ change: (inout CommunityPluginList) -> Void) throws -> CommunityPluginList {
        let graphitePath = CommunityPluginList.graphiteConfigurationPath
        if try configurationData(at: graphitePath) == nil {
            // A change that changes nothing leaves the vault without a Graphite list, so
            // Graphite keeps following Obsidian's.
            let startingList = try communityPluginList()
            var updated = startingList
            change(&updated)
            if updated == startingList { return updated }
        }
        var updated = CommunityPluginList()
        try saveConfiguration(at: graphitePath) { existingData in
            let existing = try existingData.map { data in try CommunityPluginList(configurationData: data, configurationPath: graphitePath) }
                ?? obsidianListAsGraphiteRunsIt()
            updated = existing
            change(&updated)
            // An unchanged list leaves the file as it was, formatting included.
            if updated == existing, let existingData { return existingData }
            return try updated.configurationData()
        }
        return updated
    }
}
