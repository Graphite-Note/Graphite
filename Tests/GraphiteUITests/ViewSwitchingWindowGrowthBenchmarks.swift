/**
 * File: ViewSwitchingWindowGrowthBenchmarks.swift
 * -----------------------------------------------
 * Layer: Tests
 * Description: Library ↔ List timed as the window grows towards what the owner's window holds: more tabs, a split,
 *              every core plugin on, then the community plugins of a folder given by the person running it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 13/11/2026
 */
import XCTest
import SwiftUI
import GraphiteCore
@testable import GraphiteUI
#if canImport(GraphiteTestSupport)
import GraphiteTestSupport
#endif

/// The owner measured Library → List at 1.2 to 3.7 s; `testSwitchingViewsInAVaultOfTheOwnersSize` reaches about 0.2 s.
/// This benchmark grows the same window one step at a time and times Library → List after each, with one
/// `GRAPHITE-SWITCH` line per step. `GRAPHITE_COMMUNITY_PLUGINS_FOLDER` names a folder of plugin folders (each with its
/// `manifest.json` and `main.js`) the vault enables in the last step; without it that step is left out.
/// `GRAPHITE_BENCHMARKS=1 swift test -c release -Xswiftc -enable-testing --filter PerformanceBenchmarkTests/testLibraryToList`
extension PerformanceBenchmarkTests {
    private static let growthSwitchCount = 4

    func testLibraryToListAsTheWindowGrowsTowardsTheOwners() async throws {
        let shape = OwnerShapedVault.ownersSize
        let pluginsFolder = ProcessInfo.processInfo.environment["GRAPHITE_COMMUNITY_PLUGINS_FOLDER"].map { path in URL(fileURLWithPath: path) }
        let (workspace, window) = try await ViewSwitchingWindow.open(shape, for: self) { vault in
            if let pluginsFolder { try Self.copyCommunityPlugins(from: pluginsFolder, into: vault) }
        }
        let quietWatch = MainThreadQuietWatch(window: window)

        func measureLibraryRoundTrips(_ scenario: String) async throws {
            var toList: [MainThreadQuietWatch.Measurement] = []
            for _ in 0..<Self.growthSwitchCount {
                _ = try await quietWatch.measure { workspace.preferences.library.presentation = .library }
                toList.append(try await quietWatch.measure { workspace.preferences.library.presentation = .list })
            }
            MainThreadQuietWatch.report(scenario: "library-to-list-" + scenario, shape: shape, measurements: toList)
        }

        try await measureLibraryRoundTrips("six-tabs")
        workspace.preferences.library.presentation = .list
        let notes = try FileManager.default.contentsOfDirectory(atPath: try XCTUnwrap(workspace.folderAccess?.root).appendingPathComponent("Course 1").path)
            .filter { name in name.hasSuffix(".md") }.sorted().prefix(10)
        for name in notes { await workspace.open(try VaultPath("Course 1/" + name), placement: .newTab) }
        try await measureLibraryRoundTrips("sixteen-tabs")
        workspace.preferences.library.presentation = .list
        workspace.splitRight()
        await workspace.open(try VaultPath(OwnerShapedVault.longLecturePath), placement: .currentTab)
        try await measureLibraryRoundTrips("split")
        for plugin in CorePlugin.allCases { workspace.preferences.setEnabled(plugin, true) }
        try await measureLibraryRoundTrips("every-core-plugin")
        guard pluginsFolder != nil else { return }
        let host = workspace.communityPlugins
        await host.setTurnedOnForVault(true)
        try await waitUntil("the community plugins are loaded", timeoutSeconds: 120) {
            host.isRuntimeRunning && !host.isStartingPlugins && host.loadStates.values.contains(.loaded)
        }
        // A plugin that has not loaded within a while is left out: in the made-up vault of 2026-11-13, Maps, LaTeX Suite,
        // Colors and Omnisearch were still waiting after two minutes, behind the two that loaded.
        try? await waitUntil("every plugin is loaded", timeoutSeconds: 20) {
            host.loadStates.values.allSatisfy { state in state != .notStarted && state != .loading }
        }
        let loadedPlugins = host.loadStates.filter { _, state in state == .loaded }.keys.sorted()
        print("GRAPHITE-SWITCH loaded community plugins: \(loadedPlugins.joined(separator: ", ")); not loaded: \(host.loadStates.filter { _, state in state != .loaded })")
        XCTAssertFalse(loadedPlugins.isEmpty, "The folder's plugins run in the window.")
        _ = try await quietWatch.measure {}
        try await measureLibraryRoundTrips("community-plugins")
    }

    /// Copies each plugin's code (never its `data.json`) and enables them all, as `.obsidian/community-plugins.json` does.
    private static func copyCommunityPlugins(from pluginsFolder: URL, into vault: URL) throws {
        let fileManager = FileManager.default
        let configurationFolder = vault.appendingPathComponent(".obsidian", isDirectory: true)
        var identifiers: [String] = []
        for pluginFolder in try fileManager.contentsOfDirectory(at: pluginsFolder, includingPropertiesForKeys: nil) {
            let manifest = pluginFolder.appendingPathComponent("manifest.json")
            guard fileManager.fileExists(atPath: manifest.path) else { continue }
            let destination = configurationFolder.appendingPathComponent("plugins/" + pluginFolder.lastPathComponent, isDirectory: true)
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            for fileName in ["manifest.json", "main.js", "styles.css"] {
                let source = pluginFolder.appendingPathComponent(fileName)
                if fileManager.fileExists(atPath: source.path) { try fileManager.copyItem(at: source, to: destination.appendingPathComponent(fileName)) }
            }
            identifiers.append(pluginFolder.lastPathComponent)
        }
        try JSONSerialization.data(withJSONObject: identifiers).write(to: configurationFolder.appendingPathComponent("community-plugins.json"))
    }
}
