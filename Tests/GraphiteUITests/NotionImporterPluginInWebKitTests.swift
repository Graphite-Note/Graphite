/**
 * File: NotionImporterPluginInWebKitTests.swift
 * ---------------------------------------------
 * Layer: Tests
 * Description: The Notion Importer plugin (the Swift Importer compiled to WebAssembly) importing Notion exports in
 *              WebKit on the Mac, compared file by file with the linked package's import.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 27/11/2026
 */
#if os(macOS)
import Darwin
import WebKit
import XCTest
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport
import GraphiteFixtures

/// The Mac's run of `CommunityPluginHostTests.testNotionImporterPluginImportsEachExportAsTheLinkedPackageDoes`, the
/// iPad's hosted test, in the package's tests: an app-hosted run on the Mac needs the test daemon's control session,
/// which a Mac without a person at it may not give. The plugin of `Graphite-Note/Importer` (`Plugin/build-plugin.sh`,
/// copied into `compatibility/built/graphite-notion-importer`) is installed as Graphite installs it and run as a
/// person runs it: its settings tab's Import button, the export given to the window's file input, Import, then the
/// report. Each export of `GRAPHITE_NOTION_PLUGIN_EXPORTS` (`export.zip=expected vault` pairs separated by `|`, the
/// expected vault written by the Importer's `importer` command with `--into Notion`) is imported into a vault of its
/// own and must come out as the expected vault, file by file and byte by byte. Prints the time and the most memory
/// the web content process used. Returns at once when the plugin is not built or no export is named.
@MainActor
final class NotionImporterPluginInWebKitTests: XCTestCase {
    private static let pluginIdentifier = "graphite-notion-importer"
    private static let builtPlugin = FixtureFolders.repositoryRoot
        .appendingPathComponent("Tests/CommunityPluginRuntimeTests/compatibility/built/graphite-notion-importer")
    private let testBed = CommunityPluginHostTestBed()

    override func tearDown() async throws {
        await testBed.tearDown()
    }

    func testEachExportImportsAsTheLinkedPackageDoes() async throws {
        let pairs = (ProcessInfo.processInfo.environment["GRAPHITE_NOTION_PLUGIN_EXPORTS"] ?? "")
            .split(separator: "|").compactMap { pair -> (URL, URL)? in
                let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
                return parts.count == 2 ? (URL(fileURLWithPath: parts[0]), URL(fileURLWithPath: parts[1])) : nil
            }
        guard !pairs.isEmpty else { return print("Not run: GRAPHITE_NOTION_PLUGIN_EXPORTS names no export.") }
        guard FileManager.default.fileExists(atPath: Self.builtPlugin.appendingPathComponent("main.js").path) else {
            return print("Not run: the Notion Importer plugin is not built into \(Self.builtPlugin.path).")
        }
        for (export, expectedVault) in pairs {
            let vault = try testBed.makeVault(plugins: [], files: ["Welcome.md": "# Welcome\n"])
            try install(into: vault)
            let pieces = try writeInPieces(export, into: vault)
            let workspace = try await testBed.openWorkspace(at: vault, expectedPluginCount: 1)
            let host = workspace.communityPlugins
            await host.setTurnedOnForVault(true)
            try await waitUntil("the plugin loads", timeoutSeconds: 30) { host.loadStates[Self.pluginIdentifier] == .loaded }
            let summary = try await runPlugin(in: host, exportPieces: pieces, exportName: export.lastPathComponent)
            let memory = webContentFootprint(of: host)
            print("""
                Notion Importer plugin on the Mac, \(export.lastPathComponent): \(summary["notes"] ?? "?") notes, \
                \(summary["bases"] ?? "?") bases, \(summary["attachments"] ?? "?") attachments, failed \(summary["failed"] ?? "?"), \
                in \(summary["seconds"] ?? "?") s; web content \(memory.current) MB after, \(memory.peak) MB at most
                """)
            XCTAssertEqual(summary["failed"] as? Int, 0, "\(summary)")
            let differences = try vaultDifferences(expected: expectedVault.appendingPathComponent("Notion"),
                                                   imported: vault.appendingPathComponent("Notion"))
            XCTAssertEqual(differences, [], "\(export.lastPathComponent) imports as the linked package does")
            try assertSamePropertyTypes(expected: expectedVault, imported: vault, export: export.lastPathComponent)
            await host.setTurnedOnForVault(false)
        }
    }

    /// The built plugin's files copied into the vault and the plugin listed as enabled, as the installer leaves them.
    private func install(into vault: URL) throws {
        let folder = vault.appendingPathComponent(".obsidian/plugins/" + Self.pluginIdentifier)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for file in ["main.js", "manifest.json", "styles.css"] where FileManager.default.fileExists(atPath: Self.builtPlugin.appendingPathComponent(file).path) {
            try Data(contentsOf: Self.builtPlugin.appendingPathComponent(file)).write(to: folder.appendingPathComponent(file))
        }
        try Data("[\"\(Self.pluginIdentifier)\"]".utf8).write(to: vault.appendingPathComponent(".obsidian/community-plugins.json"))
    }

    /// The export copied into the vault's `Picked` folder in pieces of 64 MB, since the plugin panel serves no file over
    /// 256 MB, and the pieces' paths in order.
    private func writeInPieces(_ export: URL, into vault: URL) throws -> [String] {
        try FileManager.default.createDirectory(at: vault.appendingPathComponent("Picked"), withIntermediateDirectories: true)
        let reader = try FileHandle(forReadingFrom: export)
        defer { try? reader.close() }
        var paths: [String] = []
        while let piece = try reader.read(upToCount: 64 * 1_048_576), !piece.isEmpty {
            let path = "Picked/\(export.lastPathComponent).\(paths.count)"
            try piece.write(to: vault.appendingPathComponent(path))
            paths.append(path)
        }
        return paths
    }

    /// Opens the plugin's settings, its import window, gives the file input the export (its pieces read from the vault
    /// and joined into one `File`, since no person picks it here), presses Import and waits for the report.
    private func runPlugin(in host: CommunityPluginHost, exportPieces: [String], exportName: String) async throws -> [String: Any] {
        let hasSettings = await host.showSettings(of: Self.pluginIdentifier)
        XCTAssertTrue(hasSettings, "the plugin has its settings tab")
        let webView = try XCTUnwrap(host.webView)
        let script = """
            const pause = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds));
            const app = window.GraphitePluginRuntime.app;
            const pieces = [];
            for (const piecePath of exportPieces) {
                const response = await fetch(app.vault.adapter.getResourcePath(piecePath));
                if (!response.ok) throw new Error('The test could not read ' + piecePath + ': ' + response.status);
                pieces.push(await response.blob());
            }
            const exportFile = new File(pieces, exportName, { type: 'application/zip' });
            const importButton = Array.from(document.querySelectorAll('.setting-item button')).find((button) => button.textContent === 'Import…');
            if (!importButton) throw new Error('No Import… button in the settings tab');
            importButton.click();
            await pause(200);
            const input = document.querySelector('.notion-importer input[type=file]');
            if (!input) throw new Error('No file input in the import window');
            Object.defineProperty(input, 'files', { value: [exportFile], configurable: true });
            input.dispatchEvent(new Event('change'));
            const windowButtons = () => Array.from(document.querySelectorAll('.notion-importer button'));
            const start = windowButtons().find((button) => button.textContent === 'Import');
            if (!start || start.disabled) throw new Error('The Import button is not ready');
            start.click();
            const deadline = Date.now() + timeoutMilliseconds;
            while (!windowButtons().some((button) => button.textContent === 'Open the report')) {
                const status = (document.querySelector('.notion-importer-status') || {}).textContent || '';
                if (status.startsWith('The import failed')) throw new Error(status);
                if (Date.now() > deadline) throw new Error('The import did not finish: ' + status);
                await pause(200);
            }
            const summary = Object.assign({}, app.plugins.plugins[pluginIdentifier].lastSummary);
            document.querySelector('.notion-importer').closest('.modal-container')?.querySelector('.modal-close-button')?.click();
            return summary;
            """
        let arguments: [String: Any] = ["exportPieces": exportPieces, "exportName": exportName, "timeoutMilliseconds": 3_600_000,
                                        "pluginIdentifier": Self.pluginIdentifier]
        let answer = try await webView.callAsyncJavaScript(script, arguments: arguments, in: nil, contentWorld: .page)
        return try XCTUnwrap(answer as? [String: Any])
    }

    /// The physical footprint of the web content process running the plugins, in MB: now and the most it used.
    private func webContentFootprint(of host: CommunityPluginHost) -> (current: Int, peak: Int) {
        guard let identifier = host.webView?.value(forKey: "_webProcessIdentifier") as? Int32, identifier > 0 else { return (-1, -1) }
        var usage = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(identifier, RUSAGE_INFO_V4, $0) }
        }
        guard result == 0 else { return (-1, -1) }
        return (Int(usage.ri_phys_footprint / 1_048_576), Int(usage.ri_lifetime_max_phys_footprint / 1_048_576))
    }

    /// The files that differ between two folders, compared byte by byte, paths in Unicode's composed form.
    private func vaultDifferences(expected: URL, imported: URL) throws -> [String] {
        func files(in folder: URL) throws -> [String: URL] {
            var found: [String: URL] = [:]
            guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isDirectoryKey]) else { return [:] }
            for case let location as URL in enumerator where try location.resourceValues(forKeys: [.isDirectoryKey]).isDirectory != true {
                let path = String(location.standardizedFileURL.path.dropFirst(folder.standardizedFileURL.path.count + 1))
                found[path.precomposedStringWithCanonicalMapping] = location
            }
            return found
        }
        let expectedFiles = try files(in: expected)
        let importedFiles = try files(in: imported)
        var differences = Set(expectedFiles.keys).symmetricDifference(importedFiles.keys).map { path in "only in one: " + path }
        for (path, location) in expectedFiles {
            guard let other = importedFiles[path] else { continue }
            if try Data(contentsOf: location) != Data(contentsOf: other) { differences.append("differs: " + path) }
        }
        return differences.sorted()
    }

    private func assertSamePropertyTypes(expected: URL, imported: URL, export: String) throws {
        let expectedTypes = expected.appendingPathComponent(".obsidian/types.json")
        guard FileManager.default.fileExists(atPath: expectedTypes.path) else { return }
        let read = { (location: URL) in try JSONSerialization.jsonObject(with: Data(contentsOf: location)) as? NSDictionary }
        XCTAssertEqual(try read(imported.appendingPathComponent(".obsidian/types.json")), try read(expectedTypes),
                       "\(export): the same property types")
    }
}
#endif
