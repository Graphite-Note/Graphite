/**
 * File: CommunityPluginVaultBridgeAppendTests.swift
 * -------------------------------------------------
 * Layer: Tests
 * Description: A plugin's appendBinary adds its bytes at the end of the file in place, so a file larger than one write
 *              is written in pieces, each no larger than a write.
 *
 * Authors: Bahey Shalash
 * Version: 1.0
 * Date: 27/11/2026
 */

import XCTest
@testable import GraphiteCore
import GraphiteTestSupport

/// Importers write a large attachment (a lecture recording of hundreds of MB) piece by piece with `appendBinary`.
/// `vault.write` accepts a file of 64 MB at most and the runtime used to read the whole file back before each piece.
/// These check that `vault.append` adds the bytes to the file on disk, makes a missing file, and refuses a folder
/// and a piece larger than a write.
final class CommunityPluginVaultBridgeAppendTests: XCTestCase {
    private var vault: URL!

    override func setUpWithError() throws {
        vault = try TemporaryVault.make(prefix: "PluginAppend", for: self).root
    }

    private func respond(_ message: [String: Any]) async throws -> [String: Any] {
        let bridge = CommunityPluginVaultBridge(store: VaultStore(root: vault)) { .permanent }
        let answer = await bridge.respond(to: try JSONSerialization.data(withJSONObject: message))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: answer) as? [String: Any])
    }

    func testPiecesAreAddedInOrderToANewFileWhoseSizeTheAnswerGives() async throws {
        let pieces = [Data(repeating: 1, count: 3_000_000), Data(repeating: 2, count: 3_000_000), Data([3, 4])]
        var answer: [String: Any] = [:]
        for piece in pieces {
            answer = try await respond(["operation": "vault.append", "path": "Notion/Recordings/week 1.mp4", "base64": piece.base64EncodedString()])
            XCTAssertNil(answer["failure"], "\(answer)")
        }
        let written = try Data(contentsOf: vault.appendingPathComponent("Notion/Recordings/week 1.mp4"))
        XCTAssertEqual(written, pieces.reduce(Data(), +))
        let stat = try XCTUnwrap(answer["stat"] as? [String: Any])
        XCTAssertEqual(stat["size"] as? Int, 6_000_002)
    }

    func testAnExistingFileKeepsWhatItHad() async throws {
        try Data("first ".utf8).write(to: vault.appendingPathComponent("Log.txt"))
        let answer = try await respond(["operation": "vault.append", "path": "Log.txt", "base64": Data("second".utf8).base64EncodedString()])
        XCTAssertNil(answer["failure"], "\(answer)")
        XCTAssertEqual(try String(contentsOf: vault.appendingPathComponent("Log.txt"), encoding: .utf8), "first second")
    }

    func testAFolderAndAPieceLargerThanAWriteAreRefused() async throws {
        try FileManager.default.createDirectory(at: vault.appendingPathComponent("Folder"), withIntermediateDirectories: true)
        let folderAnswer = try await respond(["operation": "vault.append", "path": "Folder", "base64": Data([1]).base64EncodedString()])
        XCTAssertEqual((folderAnswer["failure"] as? [String: Any])?["kind"] as? String, "isFolder")
        let tooLarge = Data(count: CommunityPluginVaultBridge.maximumTransferredBytes + 1).base64EncodedString()
        let largeAnswer = try await respond(["operation": "vault.append", "path": "Large.bin", "base64": tooLarge])
        XCTAssertEqual((largeAnswer["failure"] as? [String: Any])?["kind"] as? String, "tooLarge")
        XCTAssertFalse(FileManager.default.fileExists(atPath: vault.appendingPathComponent("Large.bin").path))
    }
}
