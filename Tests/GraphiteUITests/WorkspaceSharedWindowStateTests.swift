/**
 * File: WorkspaceSharedWindowStateTests.swift
 * -------------------------------------------
 * Layer: Tests
 * Description: Two windows on one vault: recent files, the tabs of a vault opened again, and a new window's opening.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import XCTest
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

/// Windows of one process share the device's state of a vault (`ProcessServices`); each has
/// tabs of its own.
@MainActor
final class WorkspaceSharedWindowStateTests: XCTestCase {
    private var device: IsolatedWorkspaceDevice!
    private var processServices: ProcessServices!

    override func setUp() async throws {
        device = try IsolatedWorkspaceDevice.make(for: self)
        processServices = device.makeServices()
    }

    private func makeVault(files: [String]) throws -> URL {
        let vault = try TemporaryVault.make(prefix: "SharedWindowVault", for: self).root.resolvingSymlinksInPath()
        for file in files { try Data("\(file).".utf8).write(to: vault.appendingPathComponent(file)) }
        return vault
    }

    private func makeWindow(opening vault: URL) async throws -> WorkspaceModel {
        let window = WorkspaceModel(processServices: processServices, clock: LiveApplicationClock())
        try await window.openFolderAsVault(vault)
        return window
    }

    private func openFilePaths(of window: WorkspaceModel) -> [String] {
        window.layout.allTabs.compactMap { tab in tab.path?.rawValue }
    }

    /// HUNT-192: each window kept its own copy of the list and wrote the whole list over the
    /// other's, so neither saw what the other opened.
    func testTwoWindowsOnOneVaultShareTheirRecentFiles() async throws {
        let vault = try makeVault(files: ["A.md", "B.md"])
        let firstWindow = try await makeWindow(opening: vault)
        let secondWindow = try await makeWindow(opening: vault)

        await firstWindow.open(try VaultPath("A.md"))
        await secondWindow.open(try VaultPath("B.md"))

        XCTAssertEqual(firstWindow.recentFiles.paths.map(\.rawValue), ["B.md", "A.md"])
        XCTAssertEqual(secondWindow.recentFiles.paths.map(\.rawValue), ["B.md", "A.md"])
        let identifier = try XCTUnwrap(firstWindow.currentVaultIdentifier)
        XCTAssertEqual(device.defaults.stringArray(forKey: "GraphiteRecentFiles." + identifier.uuidString), ["B.md", "A.md"],
                       "The device keeps the list as the last change left it, under the same key as before.")
    }

    func testRecentFilesOfAVaultStayWithItWhileAnotherWindowShowsAnotherVault() async throws {
        let firstVault = try makeVault(files: ["A.md"])
        let secondVault = try makeVault(files: ["Z.md"])
        let firstWindow = try await makeWindow(opening: firstVault)
        let secondWindow = try await makeWindow(opening: secondVault)

        await firstWindow.open(try VaultPath("A.md"))
        await secondWindow.open(try VaultPath("Z.md"))

        XCTAssertEqual(firstWindow.recentFiles.paths.map(\.rawValue), ["A.md"])
        XCTAssertEqual(secondWindow.recentFiles.paths.map(\.rawValue), ["Z.md"])
    }

    /// HUNT-194: a window whose vault opened again where it is (its folder moved) came back with
    /// the tabs of whichever window changed its tabs last.
    func testAWindowWhoseVaultOpensAgainKeepsItsOwnTabs() async throws {
        let vault = try makeVault(files: ["Mine.md", "Theirs.md"])
        let myWindow = try await makeWindow(opening: vault)
        let otherWindow = try await makeWindow(opening: vault)
        await myWindow.open(try VaultPath("Mine.md"))
        // The other window saves its tabs last, over the vault's one saved layout.
        await otherWindow.open(try VaultPath("Theirs.md"))

        await myWindow.vaultFolderDidMove(to: vault)

        XCTAssertEqual(openFilePaths(of: myWindow), ["Mine.md"])
        XCTAssertEqual(openFilePaths(of: otherWindow), ["Theirs.md"])
    }

    /// HUNT-187: a window opened by a dragged file asks to restore the vault's last tabs and to
    /// open the vault with that file at once; the two openings interleaved.
    func testAWindowAskedToRestoreAndToShowAFileEndsShowingTheFile() async throws {
        let vault = try makeVault(files: ["Old.md", "Dragged.md"])
        let firstWindow = try await makeWindow(opening: vault)
        await firstWindow.open(try VaultPath("Old.md"))
        let vaultIdentifier = try XCTUnwrap(firstWindow.currentVaultIdentifier)
        let newWindow = WorkspaceModel(processServices: processServices, clock: LiveApplicationClock())
        let draggedPath = try VaultPath("Dragged.md")

        async let restoring: Void = newWindow.restoreVault()
        async let showing: Void = newWindow.openVaultOfWindow(vaultIdentifier, tabs: .none, showing: draggedPath)
        _ = await (restoring, showing)

        XCTAssertEqual(openFilePaths(of: newWindow), ["Dragged.md"], "Not the vault's old tabs, and not both.")
        XCTAssertEqual(newWindow.selection?.rawValue, "Dragged.md")
    }

    func testAWindowAskedToShowAFileThenToRestoreStillShowsTheFile() async throws {
        let vault = try makeVault(files: ["Old.md", "Dragged.md"])
        let firstWindow = try await makeWindow(opening: vault)
        await firstWindow.open(try VaultPath("Old.md"))
        let vaultIdentifier = try XCTUnwrap(firstWindow.currentVaultIdentifier)
        let newWindow = WorkspaceModel(processServices: processServices, clock: LiveApplicationClock())
        let draggedPath = try VaultPath("Dragged.md")

        async let showing: Void = newWindow.openVaultOfWindow(vaultIdentifier, tabs: .none, showing: draggedPath)
        async let restoring: Void = newWindow.restoreVault()
        _ = await (showing, restoring)

        XCTAssertEqual(openFilePaths(of: newWindow), ["Dragged.md"])
    }
}
