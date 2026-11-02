/**
 * File: SplitDividerDragTests.swift
 * ---------------------------------
 * Layer: Tests
 * Description: Dragging the divider between two sides saves the layout once, and a tab dropped from another window.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import XCTest
import GraphiteCore
@testable import GraphiteUI

@MainActor
final class SplitDividerDragTests: XCTestCase {
    private let testBed = WorkspaceModelTestBed()

    override func tearDown() async throws {
        testBed.tearDown()
    }

    func testTheSplitFollowsTheFingerWithinTheAllowedRange() {
        var drag = SplitDividerDrag()
        XCTAssertNil(drag.fraction)

        XCTAssertEqual(drag.change(translation: 100, availableWidth: 1_000, layoutFraction: 0.5), 0.6, accuracy: 0.0001)
        XCTAssertEqual(drag.change(translation: -200, availableWidth: 1_000, layoutFraction: 0.5), 0.3, accuracy: 0.0001, "Measured from where the drag began, not from the last frame.")
        XCTAssertEqual(drag.change(translation: -900, availableWidth: 1_000, layoutFraction: 0.5), TabLayout.splitFractionRange.lowerBound)
        XCTAssertEqual(drag.change(translation: 900, availableWidth: 1_000, layoutFraction: 0.5), TabLayout.splitFractionRange.upperBound)
    }

    func testTheDragEndsOnceWithTheSplitToKeep() {
        var drag = SplitDividerDrag()
        _ = drag.change(translation: 50, availableWidth: 1_000, layoutFraction: 0.5)
        _ = drag.change(translation: 80, availableWidth: 1_000, layoutFraction: 0.5)

        XCTAssertEqual(try XCTUnwrap(drag.end()), 0.58, accuracy: 0.0001)
        XCTAssertNil(drag.fraction)
        XCTAssertNil(drag.end(), "A drag that did not move leaves the layout alone.")
        XCTAssertEqual(drag.change(translation: 10, availableWidth: 1_000, layoutFraction: 0.58), 0.59, accuracy: 0.0001, "The next drag begins from the layout's split.")
    }

    /// HUNT-185: every frame of a drag assigned the layout, which encoded it and wrote it to the
    /// device. Fifty frames of a drag now change the saved layout once.
    func testADragOfManyFramesChangesTheSavedLayoutOnce() async throws {
        let (workspace, _) = try await testBed.openedWorkspace(files: ["A.md": "A.", "B.md": "B."])
        try await testBed.open("A.md", in: workspace)
        workspace.splitRight()
        let changesBefore = workspace.savedLayoutChangeCount
        var drag = SplitDividerDrag()

        for frame in 1...50 {
            _ = drag.change(translation: CGFloat(frame), availableWidth: 1_000, layoutFraction: workspace.layout.splitFraction)
        }
        XCTAssertEqual(workspace.savedLayoutChangeCount, changesBefore, "Nothing is saved while the finger moves.")
        if let draggedFraction = drag.end() { workspace.layout.splitFraction = draggedFraction }

        XCTAssertEqual(workspace.savedLayoutChangeCount, changesBefore + 1)
        XCTAssertEqual(workspace.layout.splitFraction, 0.55, accuracy: 0.0001)
    }

    func testTheSavedLayoutCountIgnoresChangesThatAreNotSaved() async throws {
        let (workspace, _) = try await testBed.openedWorkspace(files: ["A.md": "A.", "B.md": "B."])
        try await testBed.open("A.md", in: workspace)
        try await testBed.open("B.md", in: workspace)
        let changesBefore = workspace.savedLayoutChangeCount

        await workspace.goBack()
        XCTAssertGreaterThan(workspace.savedLayoutChangeCount, changesBefore, "Going back shows another file, which is saved.")
        let changesAfterBack = workspace.savedLayoutChangeCount
        workspace.layout = workspace.layout
        XCTAssertEqual(workspace.savedLayoutChangeCount, changesAfterBack)
    }

    // MARK: Tabs dropped from another window

    /// HUNT-196: a tab of another window was refused, as its identifier is not in this layout.
    func testATabDroppedFromAnotherWindowOnTheSameVaultOpensItsFile() throws {
        let vaultIdentifier = UUID()
        var layout = TabLayout()
        layout.show(try VaultPath("Here.md"), inTab: layout.activeTab.id, recordsHistory: true)
        let fromAnotherWindow = TabTransfer(tabID: UUID(), path: "There.md", vaultIdentifier: vaultIdentifier)

        XCTAssertEqual(fromAnotherWindow.drop(in: layout, vaultIdentifier: vaultIdentifier), .openFile(try VaultPath("There.md")))
        XCTAssertEqual(fromAnotherWindow.drop(in: layout, vaultIdentifier: UUID()), .refused, "A file of another vault has no place here.")
        XCTAssertEqual(fromAnotherWindow.drop(in: layout, vaultIdentifier: nil), .refused)
        XCTAssertEqual(TabTransfer(tabID: UUID(), path: nil, vaultIdentifier: vaultIdentifier).drop(in: layout, vaultIdentifier: vaultIdentifier), .refused, "A tab without a file has nothing to open.")
    }

    func testATabOfThisWindowStillMoves() throws {
        var layout = TabLayout()
        layout.show(try VaultPath("Here.md"), inTab: layout.activeTab.id, recordsHistory: true)
        let tabID = layout.activeTab.id

        XCTAssertEqual(TabTransfer(tabID: tabID, path: "Here.md", vaultIdentifier: UUID()).drop(in: layout, vaultIdentifier: nil), .moveTab(tabID))
        XCTAssertEqual(TabTransfer(tabID: tabID).drop(in: layout, vaultIdentifier: nil), .moveTab(tabID))
    }

    func testATabTransferWithoutFileOrVaultKeepsItsEarlierJSON() throws {
        let tabID = try XCTUnwrap(UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        let encoded = try JSONEncoder().encode(TabTransfer(tabID: tabID))
        XCTAssertEqual(try JSONSerialization.jsonObject(with: encoded) as? [String: String], ["tabID": "11111111-2222-3333-4444-555555555555"])
        let withFile = try JSONDecoder().decode(TabTransfer.self, from: try JSONEncoder().encode(TabTransfer(tabID: tabID, path: "A.md", vaultIdentifier: tabID)))
        XCTAssertEqual(withFile.path, "A.md")
        XCTAssertEqual(withFile.vaultIdentifier, tabID)
    }
}
