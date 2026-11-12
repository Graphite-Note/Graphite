/**
 * File: GraphTabHostedTests.swift
 * -------------------------------
 * Layer: Tests
 * Description: The whole vault's graph in the iPad's window: a tab split beside a note, a node opened from it on the
 *              other side while the graph stays, the graph brought back with the window's tabs, and its look in light
 *              and dark on a small demo vault of made-up course notes.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 11/11/2026
 */

#if os(iOS)
import XCTest
import SwiftUI
import GraphiteCore
@testable import GraphiteUI

/// The graph's tab in the whole window on the iPad simulator, found by what an assistive
/// technology reads: the canvas is named "Graph of …" and lists its nodes as buttons. The
/// vault is a dozen made-up lecture notes of two courses, never a person's notes. Nothing here
/// plays sound.
@MainActor
final class GraphTabHostedTests: SettingsHostedTestCase {
    /// Two made-up courses whose lectures link each other and carry a course's tag, and two
    /// notes without links.
    private static let demoNotes: [String: String] = [
        "Signals/Sampling.md": "#course/signals\n\nThe sampling theorem. See [[Aliasing]] and [[Fourier transform]].\n",
        "Signals/Aliasing.md": "#course/signals\n\nFrequencies above half the rate fold back. Back to [[Sampling]].\n",
        "Signals/Fourier transform.md": "#course/signals #transforms\n\nSee [[Convolution]].\n",
        "Signals/Convolution.md": "#course/signals\n\nA product in frequency: [[Fourier transform]].\n",
        "Signals/Filters.md": "#course/signals #transforms\n\nA low-pass filter before [[Sampling]].\n",
        "Circuits/Inverter.md": "#course/circuits\n\nThe delay of an inverter; see [[Logical effort]].\n",
        "Circuits/Logical effort.md": "#course/circuits #sizing\n\nSizing a chain: [[Inverter]], [[Fanout]].\n",
        "Circuits/Fanout.md": "#course/circuits #sizing\n\nA fanout of four.\n",
        "Circuits/Power.md": "#course/circuits\n\nEnergy per transition of an [[Inverter]].\n",
        "Circuits/Wires.md": "#course/circuits\n\nThe delay of wires: [[Inverter]], [[Fanout]].\n",
        "Inbox/Reading list.md": "Books to read.\n",
        "Inbox/Exam dates.md": "Friday.\n",
    ]

    private static let windowSize = CGSize(width: 1180, height: 820)

    private func openDemoVault(in workspace: WorkspaceModel) async throws -> URL {
        let vault = try TemporaryVault.make(prefix: "GraphTabHosted", files: Self.demoNotes, for: self).root
        try await workspace.openFolderAsVault(vault)
        try await waitUntil("the vault is indexed") { workspace.hasCompletedIndexScan }
        return vault
    }

    /// The window with its sidebar hidden, so the split has the window's width.
    private func showWindow(of workspace: WorkspaceModel) throws -> UIViewController {
        try host(GraphiteRootView(workspace: workspace), size: Self.windowSize, horizontalSizeClass: .regular)
    }

    /// A node of the graph as VoiceOver lists it, a button the size of the canvas, once the
    /// corner counts the vault's notes.
    private func graphCanvas(in controller: UIViewController) async throws -> NSObject {
        _ = try await element(in: controller, "the graph's count of notes") { object in
            object.accessibilityLabel?.hasPrefix("12 notes · 4 tags") == true
        }
        return try await element(in: controller, "the graph's node Fanout") { object in
            object.accessibilityLabel == "Fanout" && object.accessibilityTraits.contains(.button)
        }
    }

    private func attachScreenshot(named name: String) {
        guard let window else { return }
        let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Lets the layout settle, so a screenshot shows the graph as it stays.
    private func waitForTheLayoutToSettle() async throws {
        let settled = ContinuousClock.now + .seconds(4)
        try await waitUntil("a few seconds for the layout", timeoutSeconds: 10) { ContinuousClock.now >= settled }
    }

    func testTheGraphSplitBesideANoteOpensANodeOnTheOtherSideAndStays() async throws {
        let workspace = device.makeWorkspace()
        _ = try await openDemoVault(in: workspace)
        await workspace.open(try VaultPath("Signals/Sampling.md"))
        await workspace.open(try VaultPath("Signals/Aliasing.md"), placement: .otherGroup)
        workspace.showGraph()
        let graphTab = workspace.layout.activeTab.id
        XCTAssertEqual(workspace.layout.activeTab.coreView, .graph)
        XCTAssertEqual(workspace.layout.groups.count, 2, "The graph is in a tab of the split's second side.")

        let controller = try showWindow(of: workspace)
        let canvas = try await graphCanvas(in: controller)
        XCTAssertGreaterThan(canvas.accessibilityFrame.width, 300, "The graph takes its side of the split.")
        XCTAssertLessThan(canvas.accessibilityFrame.width, Self.windowSize.width * 0.75, "The note keeps the other side.")
        try await waitForTheLayoutToSettle()
        attachScreenshot(named: "Graph beside a note, light")
        window?.overrideUserInterfaceStyle = .dark
        try await waitUntil("the dark appearance") { self.window?.traitCollection.userInterfaceStyle == .dark }
        attachScreenshot(named: "Graph beside a note, dark")
        window?.overrideUserInterfaceStyle = .light

        // A node's button, as VoiceOver lists the canvas's nodes, opens the note beside the graph.
        let inverter = try await element(in: controller, "the node Inverter") { object in
            object.accessibilityLabel == "Inverter" && object.accessibilityTraits.contains(.button)
        }
        await follow(inverter)
        try await waitUntil("Inverter opens on the other side") { workspace.layout.groups[0].activeTab.path?.rawValue == "Circuits/Inverter.md" }
        XCTAssertEqual(workspace.layout.groups[1].activeTab.id, graphTab, "The graph stays in front on its side.")
        XCTAssertEqual(workspace.layout.tab(withID: graphTab)?.coreView, .graph)
        _ = try await graphCanvas(in: controller)
        attachScreenshot(named: "Inverter opened beside the graph")
    }

    func testTheWindowBringsTheGraphBackWithItsTabs() async throws {
        let workspace = device.makeWorkspace()
        _ = try await openDemoVault(in: workspace)
        await workspace.open(try VaultPath("Circuits/Fanout.md"))
        await workspace.open(try VaultPath("Circuits/Power.md"), placement: .otherGroup)
        workspace.showGraph()
        let vaultIdentifier = try XCTUnwrap(workspace.currentVaultIdentifier)
        let keptTabs = try XCTUnwrap(WindowTabs.layout(in: workspace.windowTabsToKeep(), forVault: vaultIdentifier))

        // As after a relaunch: a new window's workspace opens the vault with the tabs its scene kept.
        let reopened = device.makeWorkspace()
        await reopened.openVaultOfWindow(vaultIdentifier, tabs: .window(keptTabs), showing: nil)
        try await waitUntil("the vault reopened") { reopened.currentVaultIdentifier == vaultIdentifier }
        XCTAssertEqual(reopened.layout.groups.count, 2)
        XCTAssertEqual(reopened.layout.groups[1].activeTab.coreView, .graph, "The graph's tab is back, in front on its side.")
        XCTAssertEqual(reopened.layout.groups[0].activeTab.path?.rawValue, "Circuits/Fanout.md")

        let controller = try showWindow(of: reopened)
        _ = try await graphCanvas(in: controller)
        try await waitForTheLayoutToSettle()
        attachScreenshot(named: "Graph restored with the window")
    }

    /// The graph's button one tap from the file list, in the row of the panels, on the 11-inch
    /// iPad's narrow sidebar, turned and upright; before, it was in the bar's "…" menu.
    func testTheGraphButtonIsOneTapFromTheFileList() async throws {
        let workspace = device.makeWorkspace()
        _ = try await openDemoVault(in: workspace)
        await workspace.open(try VaultPath("Signals/Sampling.md"))
        for (name, size) in [("landscape", Self.windowSize), ("portrait", CGSize(width: Self.windowSize.height, height: Self.windowSize.width))] {
            let controller = try host(GraphiteRootView(workspace: workspace), size: size, horizontalSizeClass: .regular)
            let showSidebar = try await element(in: controller, "Show Sidebar") { object in object.accessibilityLabel == "Show Sidebar" }
            await follow(showSidebar)
            let graphButton = try await elementOnScreen(in: controller, "the Graph View button, in view") { object in
                object.accessibilityLabel == "Graph View" && object.accessibilityTraits.contains(.button)
            }
            attachScreenshot(named: "Sidebar, \(name)")
            await follow(graphButton)
            try await waitUntil("the graph's tab in front") { workspace.layout.activeTab.coreView == .graph }
            await workspace.open(try VaultPath("Signals/Sampling.md"))
        }
    }
}
#endif
