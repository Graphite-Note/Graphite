/**
 * File: VaultSwitchQueueTests.swift
 * ---------------------------------
 * Layer: Tests
 * Description: Vault switches take turns and only the latest pick opens its vault (HUNT-105).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import XCTest
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

@MainActor
final class VaultSwitchQueueTests: XCTestCase {
    private let testBed = WorkspaceModelTestBed()

    override func tearDown() async throws {
        testBed.tearDown()
    }

    /// Suspends a switch until the test lets it finish.
    @MainActor private final class Gate {
        private var continuation: CheckedContinuation<Void, Never>?
        private var isReleased = false

        func suspend() async {
            guard !isReleased else { return }
            await withCheckedContinuation { continuation in self.continuation = continuation }
        }

        func release() {
            isReleased = true
            continuation?.resume()
            continuation = nil
        }
    }

    func testASwitchWaitsForTheRunningOneAndRunsAfterIt() async throws {
        let queue = VaultSwitchQueue()
        let gate = Gate()
        var events: [String] = []

        let first = Task { @MainActor in
            guard await queue.begin() else { return }
            defer { queue.end() }
            events.append("first starts")
            await gate.suspend()
            events.append("first ends")
        }
        await Task.yield()
        XCTAssertTrue(queue.isBusy)
        let second = Task { @MainActor in
            guard await queue.begin() else { return }
            defer { queue.end() }
            events.append("second runs")
        }
        await Task.yield()
        XCTAssertEqual(events, ["first starts"], "The second switch does not start while the first runs.")

        gate.release()
        await first.value
        await second.value

        XCTAssertEqual(events, ["first starts", "first ends", "second runs"])
        XCTAssertFalse(queue.isBusy)
    }

    func testOnlyTheLatestOfSeveralWaitingSwitchesRuns() async throws {
        let queue = VaultSwitchQueue()
        let gate = Gate()
        var ranSwitches: [String] = []

        func switchTask(_ name: String, holding: Gate? = nil) -> Task<Void, Never> {
            Task { @MainActor in
                guard await queue.begin() else { return }
                defer { queue.end() }
                ranSwitches.append(name)
                await holding?.suspend()
            }
        }
        let first = switchTask("first", holding: gate)
        await Task.yield()
        let second = switchTask("second")
        await Task.yield()
        let third = switchTask("third")
        await Task.yield()

        gate.release()
        await first.value; await second.value; await third.value

        XCTAssertEqual(ranSwitches, ["first", "third"], "The middle pick was replaced by the later one before it began.")
        XCTAssertFalse(queue.isBusy)
    }

    func testTheQueueIsFreeAgainAfterAllSwitchesEnded() async throws {
        let queue = VaultSwitchQueue()
        let began = await queue.begin()
        XCTAssertTrue(began)
        queue.end()
        let beganAgain = await queue.begin()
        XCTAssertTrue(beganAgain)
        queue.end()
        XCTAssertFalse(queue.isBusy)
    }

    /// Two picks in a row: the vault picked last is the one the window ends on, and the one skipped is not
    /// recorded as opened. The vault picked first used to be able to finish last.
    func testTheVaultPickedLastIsTheOneTheWindowShows() async throws {
        let workspace = try testBed.isolatedDevice().makeWorkspace()
        let firstVault = try testBed.makeVault(files: ["First.md": "First\n"])
        let skippedVault = try testBed.makeVault(files: ["Skipped.md": "Skipped\n"])
        let lastVault = try testBed.makeVault(files: ["Last.md": "Last\n"])

        let firstPick = Task { @MainActor in try await workspace.openFolderAsVault(firstVault) }
        let skippedPick = Task { @MainActor in try await workspace.openFolderAsVault(skippedVault) }
        let lastPick = Task { @MainActor in try await workspace.openFolderAsVault(lastVault) }
        try await firstPick.value; try await skippedPick.value; try await lastPick.value

        XCTAssertEqual(workspace.folderAccess.map { access in WorkspaceModel.comparablePath(of: access.root) }, WorkspaceModel.comparablePath(of: lastVault))
        let knownNames = workspace.vaultLibrary.list.vaults.map { vault in vault.name }
        XCTAssertFalse(knownNames.contains(skippedVault.lastPathComponent), "A pick replaced before it began is not opened.")
    }
}
