/**
 * File: UnreadNotesInMovesTests.swift
 * -----------------------------------
 * Layer: Tests
 * Description: Notes the index never read cannot be found by their links, so a move looks at their bytes
 *              when they are on this device and says how many it could not look at when they are not.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import XCTest
import GraphiteCore
@testable import GraphiteIndex
import GraphiteTestSupport

final class UnreadNotesInMovesTests: XCTestCase {
    private func oversizedNote(linkingTo target: String) -> Data {
        Data(("[[" + target + "]]\n" + String(repeating: "x", count: 8 * 1_048_576 + 1)).utf8)
    }

    private func makeVault(_ files: [String: Data]) async throws -> (VaultIndex, URL) {
        let root = try TemporaryVault.make(prefix: "UnreadVault", for: self).root.resolvingSymlinksInPath()
        for (relativePath, contents) in files { try contents.write(to: root.appendingPathComponent(relativePath)) }
        let indexFolder = try TemporaryVault.make(prefix: "UnreadIndex", for: self).root
        let index = try VaultIndex(databaseURL: indexFolder.appendingPathComponent("index.sqlite"))
        _ = try await index.reconcile(root: root)
        return (index, root)
    }

    /// HUNT-079. Notes in the cloud have no link rows; before, nothing was said about them.
    func testNotesInTheCloudAreCountedAsNotChecked() async throws {
        let (index, root) = try await makeVault(["Target.md": Data(), "Linker.md": Data("[[Target]]".utf8), "Cloud.md": oversizedNote(linkingTo: "Target")])
        let cloudLocation = root.appendingPathComponent("Cloud.md").standardizedFileURL.path
        let operations = VaultFileOperations(store: VaultStore(root: root), index: index) { location in location.standardizedFileURL.path == cloudLocation }

        let plan = try await operations.linkUpdates(forMoving: try VaultPath("Target.md"), to: try VaultPath("Renamed.md"))

        XCTAssertEqual(plan.notesNotChecked.map(\.rawValue), ["Cloud.md"])
        XCTAssertEqual(plan.updates.map(\.path.rawValue), ["Linker.md"], "What can be read is updated as ever.")
        let report = try await operations.move(try VaultPath("Target.md"), to: try VaultPath("Renamed.md"), applying: plan)
        XCTAssertEqual(report.notesNotChecked.map(\.rawValue), ["Cloud.md"])
    }

    /// HUNT-096. A note over the limit with a link to the moved file is named; one without is not.
    func testATooLargeNoteLinkingToTheMovedFileIsReported() async throws {
        let (index, root) = try await makeVault(["Target.md": Data(), "Large.md": oversizedNote(linkingTo: "Target"), "Other large.md": oversizedNote(linkingTo: "Unrelated")])
        let operations = VaultFileOperations(store: VaultStore(root: root), index: index)
        let plan = try await operations.linkUpdates(forMoving: try VaultPath("Target.md"), to: try VaultPath("Renamed.md"))
        XCTAssertEqual(plan.notesNotUpdated, [try VaultPath("Large.md"): .tooLarge])
        XCTAssertEqual(plan.notesNotChecked, [])
    }

    func testANoteNotInUTF8LinkingToTheMovedFileIsReported() async throws {
        var latinNote = Data("[[Target]] caf".utf8)
        latinNote.append(0xE9) // é in Latin-1, which is not valid UTF-8.
        let (index, root) = try await makeVault(["Target.md": Data(), "Latin.md": latinNote])
        let operations = VaultFileOperations(store: VaultStore(root: root), index: index)
        let plan = try await operations.linkUpdates(forMoving: try VaultPath("Target.md"), to: try VaultPath("Renamed.md"))
        XCTAssertEqual(plan.notesNotUpdated, [try VaultPath("Latin.md"): .notText])
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Latin.md")), latinNote)
    }
}
