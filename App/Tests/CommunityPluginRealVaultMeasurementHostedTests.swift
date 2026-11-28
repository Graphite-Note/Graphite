/**
 * File: CommunityPluginRealVaultMeasurementHostedTests.swift
 * ----------------------------------------------------------
 * Layer: Tests
 * Description: Measures the community plugin runtime's start-up and memory in a vault of a real vault's size on the iPad and the iPhone.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 28/11/2026
 */
#if os(iOS)
import XCTest
import SwiftUI
import WebKit
import GraphiteApple
import GraphiteCore
@testable import GraphiteUI

/// The plugin runtime in a vault of a real vault's size (Docs/Community-plugins.md, the first
/// step of Next): released plugins, built from the commits the Node tests pin, installed as
/// Graphite installs them, a note with several of their code blocks in the reading view, and
/// two of their views beside it (Calendar split from the note, Recent Files in a tab on that
/// side). Run only when asked, as it needs a made-up vault and the built plugins:
/// `TEST_RUNNER_GRAPHITE_PLUGIN_MEASURE_VAULT=<folder>` names the vault, copied before it opens,
/// and `TEST_RUNNER_GRAPHITE_RUNTIME_TESTS_FOLDER` the runtime tests' folder with `compatibility/built`.
/// Each phase prints a `GRAPHITE-PLUGIN-MEASURE` line with its time and the app's footprint, then
/// holds still until the sampler outside (`Tests/CommunityPluginRuntimeTests/tools/measure-plugin-runtime.sh`) has measured
/// the plugins' web content processes and says so with the file `<vault>.sampled-<phase>`.
@MainActor
final class CommunityPluginRealVaultMeasurementHostedTests: XCTestCase {
    private var window: UIWindow?
    private var vaultDirectory: URL?
    private var openedVaultIdentifier: UUID?
    private var workspace: WorkspaceModel?
    private var sourceVault = ""

    /// The plugins measured; `GRAPHITE_PLUGIN_MEASURE_LEAVE_OUT` names any to leave out, comma-separated
    /// (Omnisearch, which Graphite leaves off for an Obsidian vault since it searches itself).
    private static let pluginIdentifiers = ["dataview", "obsidian-tasks-plugin", "calendar", "recent-files-obsidian", "obsidian-admonition",
                                            "omnisearch", "highlightr-plugin", "nldates-obsidian", "templater-obsidian"].filter { plugin in
        !(ProcessInfo.processInfo.environment["GRAPHITE_PLUGIN_MEASURE_LEAVE_OUT"] ?? "").split(separator: ",").contains(Substring(plugin))
    }

    override func tearDown() async throws {
        if let workspace {
            await workspace.communityPlugins.vaultWillClose()
            if let openedVaultIdentifier {
                workspace.vaultLibrary.remove(openedVaultIdentifier)
                CommunityPluginHost.forgetVault(openedVaultIdentifier)
            }
        }
        workspace = nil
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
        if let vaultDirectory { try? FileManager.default.removeItem(at: vaultDirectory) } // Best-effort removal of a temporary copy.
        vaultDirectory = nil
        openedVaultIdentifier = nil
    }

    func testThePluginsStartAndDrawTheirBlocksAndViewsInARealSizedVault() async throws {
        let environment = ProcessInfo.processInfo.environment
        // Returns rather than skipping: the suites' skip count may not rise (FR-93), and this is not a missing capability.
        guard let sourceVault = environment["GRAPHITE_PLUGIN_MEASURE_VAULT"] else {
            return print("Not run: the plugin runtime is measured on demand, with GRAPHITE_PLUGIN_MEASURE_VAULT naming a made-up vault.")
        }
        self.sourceVault = sourceVault
        let builtPlugins = URL(fileURLWithPath: try XCTUnwrap(environment["GRAPHITE_RUNTIME_TESTS_FOLDER"])).appendingPathComponent("compatibility/built")
        let vault = hostedTemporaryLocation(named: "PluginMeasureVault")
        vaultDirectory = vault
        try FileManager.default.copyItem(at: URL(fileURLWithPath: sourceVault), to: vault)
        for plugin in Self.pluginIdentifiers {
            let destination = vault.appendingPathComponent(".obsidian/plugins/" + plugin)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            for file in ["main.js", "manifest.json", "styles.css"] {
                let source = builtPlugins.appendingPathComponent(plugin).appendingPathComponent(file)
                if FileManager.default.fileExists(atPath: source.path) { try Data(contentsOf: source).write(to: destination.appendingPathComponent(file)) }
            }
        }
        // Graphite's own list, as when a person turns the plugins on in Graphite: from Obsidian's list alone Graphite
        // leaves out the plugins it does itself, Omnisearch among them.
        let enabledList = try JSONSerialization.data(withJSONObject: Self.pluginIdentifiers)
        try enabledList.write(to: vault.appendingPathComponent(".obsidian/community-plugins.json"))
        try FileManager.default.createDirectory(at: vault.appendingPathComponent(".graphite"), withIntermediateDirectories: true)
        try enabledList.write(to: vault.appendingPathComponent(CommunityPluginList.graphiteConfigurationPath))

        let opening = ContinuousClock.now
        let workspace = WorkspaceModel()
        self.workspace = workspace
        try await workspace.openFolderAsVault(vault)
        openedVaultIdentifier = try XCTUnwrap(workspace.currentVaultIdentifier)
        try host(workspace)
        report("vault-open", since: opening)

        let host = workspace.communityPlugins
        await host.reloadInventory()
        try await waitUntil { Set(host.inventory.plugins.map(\.id)).isSuperset(of: Self.pluginIdentifiers) }
        let starting = ContinuousClock.now
        await host.setTurnedOnForVault(true)
        try await waitUntil("every plugin loads", timeoutSeconds: 180, pollingIntervalSeconds: 0.05) {
            Self.pluginIdentifiers.allSatisfy { plugin in host.loadStates[plugin] == .loaded }
        }
        report("plugins-loaded", since: starting, detail: Self.pluginIdentifiers.map { plugin in "\(plugin)=\(String(describing: host.loadStates[plugin]))" }.joined(separator: " "))
        XCTAssertEqual(host.runtimeProblems, [:], "Problems after loading.")
        try await hold("plugins-loaded")

        let drawing = ContinuousClock.now
        let tab = try await openTab("Dashboard.md", in: workspace)
        workspace.document(for: tab).markdownSession?.viewMode = .reading
        // What each block shows, as Graphite keeps it from the plugins' drawings (`lastCodeBlockCopies`, updated with each
        // drawing). Dataview draws a query before its index of the vault is ready, with no results, and again once it is:
        // the first table, on screen, then has its 30 rows of results.
        func rowCount(_ html: String) -> Int { html.components(separatedBy: "<tr").count - 1 }
        var shown: [CommunityPluginCodeBlockCopy] = []
        try await waitUntil("the first table shows its 30 results", timeoutSeconds: 180, pollingIntervalSeconds: 0.05) {
            shown = Array(host.lastCodeBlockCopies.values)
            return shown.contains { copy in rowCount(copy.html) >= 31 && copy.height > 100 }
        }
        report("first-table-results-shown", since: drawing)
        // What every block shows then, printed: a block below the screen keeps the drawing it had when it left the screen
        // (Dataview's first one, before its index was ready) until it comes back.
        shown = Array(host.lastCodeBlockCopies.values)
        report("blocks-shown", since: drawing, detail: "copies=\(shown.count)")
        for copy in shown {
            let text = copy.html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression).split(whereSeparator: \.isWhitespace).joined(separator: " ")
            print("GRAPHITE-PLUGIN-MEASURE copy rows=\(rowCount(copy.html)) height=\(Int(copy.height)) text=\(text.prefix(140))")
        }
        let runtime = try XCTUnwrap(host.webView)
        attachScreenshot(named: "Dashboard in the reading view")
        try await hold("blocks-shown")
        attachScreenshot(named: "Dashboard once the memory was read")

        let opensViews = ContinuousClock.now
        _ = try await runtime.callAsyncJavaScript("""
            const workspace = window.GraphitePluginRuntime.app.workspace;
            await workspace.getLeaf('split').setViewState({ type: 'calendar', active: true });
            await workspace.getLeaf('tab').setViewState({ type: 'recent-files', active: true });
            """, arguments: [:], in: nil, contentWorld: .page)
        try await waitUntil("the views open", timeoutSeconds: 60) {
            workspace.tabDocuments.values.filter { document in document.pluginViewIdentifier != nil }.count >= 2
        }
        try await waitUntil("the calendar and Recent Files draw", timeoutSeconds: 60, pollingIntervalSeconds: 0.1) {
            try await runtime.callAsyncJavaScript("return document.querySelector('.calendar') !== null && document.querySelector('.recent-files-file, .nav-file, .tree-item') !== null;",
                                                  arguments: [:], in: nil, contentWorld: .page) as? Bool == true
        }
        report("views-shown", since: opensViews)
        attachScreenshot(named: "Dashboard beside the plugin views")
        try await hold("views-shown")
    }

    // MARK: Measuring

    private func report(_ phase: String, since start: ContinuousClock.Instant, detail: String = "") {
        let elapsed = ContinuousClock.now - start
        let milliseconds = elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000
        print("GRAPHITE-PLUGIN-MEASURE phase=\(phase) at=\(Date().timeIntervalSince1970) ms=\(milliseconds) app_footprint_mb=\(Self.footprintMegabytes()) \(detail)")
    }

    /// Holds still until the sampler has measured this phase from outside.
    private func hold(_ phase: String) async throws {
        print("GRAPHITE-PLUGIN-MEASURE hold-start phase=\(phase) at=\(Date().timeIntervalSince1970)")
        FileManager.default.createFile(atPath: sourceVault + ".holding-" + phase, contents: Data("\(Self.footprintMegabytes())".utf8))
        let sampled = sourceVault + ".sampled-" + phase
        try await waitUntil("the sampler measures \(phase)", timeoutSeconds: 120, pollingIntervalSeconds: 0.5) { FileManager.default.fileExists(atPath: sampled) }
        print("GRAPHITE-PLUGIN-MEASURE hold-end phase=\(phase) at=\(Date().timeIntervalSince1970) app_footprint_mb=\(Self.footprintMegabytes())")
    }

    private static func footprintMegabytes() -> Int {
        var information = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &information) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return result == KERN_SUCCESS ? Int(information.phys_footprint / 1_048_576) : -1
    }

    // MARK: Helpers

    private func openTab(_ name: String, in workspace: WorkspaceModel) async throws -> UUID {
        let path = try VaultPath(name)
        await workspace.open(path, placement: .currentTab)
        return try XCTUnwrap(workspace.layout.tabID(showing: path))
    }

    /// The workspace in a window with the plugin panel, as `CommunityPluginHostTests` hosts it.
    @discardableResult
    private func host(_ workspace: WorkspaceModel) throws -> UIHostingController<AnyView> {
        let rootView = AnyView(NavigationStack {
            WorkspacePanes(workspace: workspace, showsLinksInspector: .constant(false), create: { _ in }, showQuickSwitcher: {})
        }.modifier(CommunityPluginPresentation(workspace: workspace) {}))
        let controller = UIHostingController(rootView: rootView)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { scene in scene as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
        return controller
    }

    private func attachScreenshot(named name: String) {
        guard let window else { return }
        let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
#endif
