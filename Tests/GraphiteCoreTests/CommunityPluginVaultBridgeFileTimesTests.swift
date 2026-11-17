/**
 * File: CommunityPluginVaultBridgeFileTimesTests.swift
 * ----------------------------------------------------
 * Layer: Tests
 * Description: A plugin's write gives the file the dates it asked for, as Obsidian's DataWriteOptions do.
 *
 * Authors: Bahey Shalash
 * Version: 1.0
 * Date: 17/11/2026
 */

import XCTest
@testable import GraphiteCore
import GraphiteTestSupport

/// Importers mark each imported note with its source's time (`vault.create(path, text, { ctime, mtime })`)
/// and, importing again, keep a note whose date is later: it was edited since. These check that a
/// `vault.write` with `modified` and `created` gives the file exactly those dates, in the answer's
/// stat too, and that a write without them leaves the dates to the file system.
final class CommunityPluginVaultBridgeFileTimesTests: XCTestCase {
    private var vault: URL!

    override func setUpWithError() throws {
        vault = try TemporaryVault.make(prefix: "PluginFileTimes", for: self).root
    }

    private func respond(_ message: [String: Any]) async throws -> [String: Any] {
        let bridge = CommunityPluginVaultBridge(store: VaultStore(root: vault)) { .permanent }
        let answer = await bridge.respond(to: try JSONSerialization.data(withJSONObject: message))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: answer) as? [String: Any])
    }

    func testAWriteWithTimesGivesTheFileThoseDatesAndAnswersThem() async throws {
        let modifiedMilliseconds = 1_790_846_100_000.0
        let createdMilliseconds = 1_788_249_600_000.0
        let answer = try await respond([
            "operation": "vault.write", "path": "Notion/Lecture 1.md", "text": "Imported\n", "expectation": ["kind": "absent"],
            "modified": modifiedMilliseconds, "created": createdMilliseconds,
        ])
        XCTAssertNil(answer["failure"])
        let stat = try XCTUnwrap(answer["stat"] as? [String: Any])
        XCTAssertEqual(stat["modified"] as? Double, modifiedMilliseconds)
        XCTAssertEqual(stat["created"] as? Double, createdMilliseconds)
        let values = try vault.appendingPathComponent("Notion/Lecture 1.md").resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
        XCTAssertEqual(values.contentModificationDate?.timeIntervalSince1970, modifiedMilliseconds / 1000)
        XCTAssertEqual(values.creationDate?.timeIntervalSince1970, createdMilliseconds / 1000)
        XCTAssertEqual(try String(contentsOf: vault.appendingPathComponent("Notion/Lecture 1.md"), encoding: .utf8), "Imported\n")
    }

    func testAWriteWithoutTimesLeavesTheFileDatedNow() async throws {
        let before = Date().addingTimeInterval(-5)
        let answer = try await respond(["operation": "vault.write", "path": "Note.md", "text": "Text\n", "expectation": ["kind": "absent"]])
        let stat = try XCTUnwrap(answer["stat"] as? [String: Any])
        let modifiedMilliseconds = try XCTUnwrap(stat["modified"] as? Double)
        XCTAssertGreaterThan(modifiedMilliseconds, before.timeIntervalSince1970 * 1000)
    }
}
