/**
 * File: CommunityPluginStartUpCostTests.swift
 * -------------------------------------------
 * Layer: Tests
 * Description: What listing plugins and the vault costs at start-up, and what a keystroke sends, counted.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import XCTest
@testable import GraphiteCore
import GraphiteTestSupport

/// What listing plugins and the vault costs at start-up, counted.
final class CommunityPluginStartUpCostTests: XCTestCase {
    private var vault: URL!

    override func setUpWithError() throws {
        vault = try TemporaryVault.make(prefix: "PluginCostVault", for: self).root
    }

    private func installPlugin(_ identifier: String, mainScript: String) throws {
        let folder = vault.appendingPathComponent(".obsidian/plugins/\(identifier)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("{\"id\": \"\(identifier)\", \"name\": \"\(identifier)\", \"version\": \"1.0.0\", \"minAppVersion\": \"1.0.0\"}".utf8).write(to: folder.appendingPathComponent("manifest.json"))
        try Data(mainScript.utf8).write(to: folder.appendingPathComponent("main.js"))
    }

    private final class ScanCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var scans = 0
        var count: Int { lock.withLock { scans } }
        func add() { lock.withLock { scans += 1 } }
    }

    private func makeScanner(counting counter: ScanCounter) -> CommunityPluginModuleScanner {
        CommunityPluginModuleScanner { mainScript in
            counter.add()
            return CommunityPluginCompatibility.missingModules(in: mainScript)
        }
    }

    func testListingPluginsAtStartUpReadsNoPluginCodeAndTheSettingsPageReadsEachOnce() async throws {
        try installPlugin("first", mainScript: "require('fs')")
        try installPlugin("second", mainScript: "require('net')")
        let counter = ScanCounter()
        let scanner = makeScanner(counting: counter)
        let listed = try await VaultStore(root: vault).installedCommunityPlugins()

        let atStartUp = await scanner.inventory(listed, root: vault, isReadingCode: false)
        XCTAssertEqual(counter.count, 0, "Before this fix a launch read and regex-scanned every plugin's main.js on the vault's store.")
        XCTAssertEqual(atStartUp.plugins.map(\.compatibility.missingModules), [[], []])

        let onTheSettingsPage = await scanner.inventory(listed, root: vault, isReadingCode: true)
        XCTAssertEqual(counter.count, 2)
        XCTAssertEqual(onTheSettingsPage.plugins.map { plugin in plugin.compatibility.missingModules.map(\.name) }, [["fs"], ["net"]])

        let openedAgain = await scanner.inventory(listed, root: vault, isReadingCode: true)
        XCTAssertEqual(counter.count, 2, "Unchanged code is not read again.")
        XCTAssertEqual(openedAgain, onTheSettingsPage)
        let afterwardsAtStartUp = await scanner.inventory(listed, root: vault, isReadingCode: false)
        XCTAssertEqual(afterwardsAtStartUp, onTheSettingsPage, "What was found stays known.")
    }

    func testCodeThatChangedIsReadAgain() async throws {
        try installPlugin("first", mainScript: "require('fs')")
        let counter = ScanCounter()
        let scanner = makeScanner(counting: counter)
        let listed = try await VaultStore(root: vault).installedCommunityPlugins()
        _ = await scanner.inventory(listed, root: vault, isReadingCode: true)

        try installPlugin("first", mainScript: "require('net') // a newer, longer version")
        let scanned = await scanner.inventory(listed, root: vault, isReadingCode: true)

        XCTAssertEqual(counter.count, 2)
        XCTAssertEqual(scanned.plugins.first?.compatibility.missingModules.map(\.name), ["net"])
    }

    func testAPluginStillLoadsAndALargeVaultsListComesInPagesOfTwoThousandAtMost() async throws {
        let bridge = CommunityPluginVaultBridge(store: VaultStore(root: vault)) { .systemTrash }
        let fileCount = CommunityPluginVaultBridge.maximumListedEntriesPerPage + 50
        for position in 0..<fileCount { try Data().write(to: vault.appendingPathComponent("Note \(position).md")) }

        var paths: Set<String> = []
        var messageCount = 0
        var request: [String: Any] = ["operation": "vault.list"]
        while true {
            let answerData = await bridge.respond(to: try JSONSerialization.data(withJSONObject: request))
            let answer = try XCTUnwrap(JSONSerialization.jsonObject(with: answerData) as? [String: Any])
            let encodedEntries = try XCTUnwrap(answer["encodedEntries"] as? String, "\(answer)")
            let columns = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(encodedEntries.utf8)) as? [String: Any])
            let pagePaths = try XCTUnwrap(columns["paths"] as? [String])
            XCTAssertLessThanOrEqual(pagePaths.count, CommunityPluginVaultBridge.maximumListedEntriesPerPage)
            paths.formUnion(pagePaths)
            messageCount += 1
            guard let nextPage = answer["nextPage"] as? String else { break }
            request = ["operation": "vault.list", "nextPage": nextPage]
        }

        XCTAssertEqual(messageCount, 2, "Before this fix the whole list was one message.")
        XCTAssertEqual(paths.count, fileCount)
        let spentAnswerData = await bridge.respond(to: try JSONSerialization.data(withJSONObject: request))
        let spentAnswer = try XCTUnwrap(JSONSerialization.jsonObject(with: spentAnswerData) as? [String: Any])
        XCTAssertNotNil(spentAnswer["failure"], "A page is given once.")
    }

    // MARK: A keystroke

    func testAKeystrokeInALongNoteIsAFewBytesWhateverTheCharactersAround() throws {
        let longNote = String(repeating: "Lecture notes über Rechnerarchitektur 🧮.\n", count: 12_000)
        XCTAssertGreaterThan(longNote.utf16.count, 400_000)
        let position = longNote.index(longNote.startIndex, offsetBy: 300_000)
        var typed = longNote
        typed.insert("x", at: position)

        let change = CommunityPluginTextChange.between(longNote, typed)

        XCTAssertEqual(change.insertedText, "x")
        XCTAssertEqual(change.removedLength, 0)
        XCTAssertEqual(change.originalLength, longNote.utf16.count)
        XCTAssertEqual(applied(change, to: longNote), typed)
    }

    func testAChangeNeverCutsACharacterInHalf() {
        for (original, changed) in [
            ("a🧮b", "a🧮🧮b"), ("a🧮b", "ab"), ("é", "è"), ("🧮", "🧪"), ("", "new"), ("old", ""), ("same", "same"), ("aXb", "aYb"), ("ab", "aab"),
        ] {
            let change = CommunityPluginTextChange.between(original, changed)
            XCTAssertEqual(applied(change, to: original), changed, "\(original) → \(changed)")
            XCTAssertEqual(change.originalLength, original.utf16.count)
        }
    }

    /// The change applied as the plugins' page applies it, by UTF-16 offsets.
    private func applied(_ change: CommunityPluginTextChange, to text: String) -> String {
        let units = Array(text.utf16)
        let result = units[..<change.location] + Array(change.insertedText.utf16) + units[(change.location + change.removedLength)...]
        return String(decoding: Array(result), as: UTF16.self)
    }
}
