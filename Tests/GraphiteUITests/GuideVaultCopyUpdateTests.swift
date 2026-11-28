/**
 * File: GuideVaultCopyUpdateTests.swift
 * -------------------------------------
 * Layer: Tests
 * Description: The reader's copy of the Graphite Guide is brought up to a newer pack: the Guide's unchanged files are
 *              replaced, new pages added, the reader's edits and deletions kept (Docs/Guide-vault-todo.md, section 7).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 28/11/2026
 */

import XCTest
import CryptoKit
import GraphiteCore
import GraphiteTestSupport
@testable import GraphiteUI

final class GuideVaultCopyUpdateTests: XCTestCase {
    private var root: URL!
    private var copyFolder: URL!
    private var earlierPack: AddOnPack!

    /// The earlier pack, as the reader's copy was made from it.
    private let earlierFiles = [
        "Start here.md": "# Welcome",
        "1 New to files/What a vault is.md": "A folder.",
        "1 New to files/Backups.md": "Copy the folder.",
        "Old page.md": "Dropped later.",
        ".obsidian/types.json": "{}",
        "Attachments/Cover.png": "cover one",
    ]
    /// The pack the app pins now.
    private let newerFiles = [
        "Start here.md": "# Welcome, with dashboards",
        "1 New to files/What a vault is.md": "A folder of files.",
        "1 New to files/Backups.md": "Copy the folder.",
        "1 New to files/Moving in from Notion.md": "Export as HTML.",
        "6 Everyday examples/Signals and Sound/Signals and Sound.md": "A course.",
        "6 Everyday examples/Signals and Sound/Week 1 - Sampling.md": "Samples.",
        ".obsidian/types.json": "{\"due\": \"date\"}",
        "Attachments/Cover.png": "cover two",
    ]

    override func setUpWithError() throws {
        root = try TemporaryVault.make(prefix: "GuideVaultCopyUpdateTests", for: self).root
        let earlierFolder = try write(earlierFiles, into: "earlier")
        earlierPack = try Self.pack(of: earlierFolder, revision: "earlier")
        copyFolder = root.appendingPathComponent("Documents/Graphite Guide", isDirectory: true)
        try FileManager.default.createDirectory(at: copyFolder.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: earlierFolder, to: copyFolder)
    }

    func testUnchangedFilesAreReplacedNewPagesAddedAndDroppedPagesRemoved() throws {
        let changes = try update(previousFileNames: Set(earlierFiles.keys))

        XCTAssertEqual(changes["Start here.md"], .replaced)
        XCTAssertEqual(changes["1 New to files/What a vault is.md"], .replaced)
        XCTAssertNil(changes["1 New to files/Backups.md"], "The same in both packs: nothing to do.")
        XCTAssertEqual(changes["1 New to files/Moving in from Notion.md"], .added)
        XCTAssertEqual(changes["6 Everyday examples/Signals and Sound/Signals and Sound.md"], .added)
        XCTAssertEqual(changes[".obsidian/types.json"], .replaced)
        XCTAssertEqual(changes["Attachments/Cover.png"], .replaced)
        XCTAssertEqual(changes["Old page.md"], .removed)
        for (name, contents) in newerFiles { XCTAssertEqual(try text(name), contents, name) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: copyFolder.appendingPathComponent("Old page.md").path))
    }

    func testANoteTheReaderChangedIsKeptWithTheNewVersionBesideIt() throws {
        try Data("# Welcome\n\nMy own line.".utf8).write(to: copyFolder.appendingPathComponent("Start here.md"))
        try Data("Kept, as I wrote it.".utf8).write(to: copyFolder.appendingPathComponent("Old page.md"))
        try Data("{\"mine\": \"text\"}".utf8).write(to: copyFolder.appendingPathComponent(".obsidian/types.json"))

        let changes = try update(previousFileNames: Set(earlierFiles.keys))

        XCTAssertEqual(changes["Start here.md"], .keptWithNewVersionBeside(besidePath: "Start here (Guide update).md"))
        XCTAssertEqual(try text("Start here.md"), "# Welcome\n\nMy own line.")
        XCTAssertEqual(try text("Start here (Guide update).md"), "# Welcome, with dashboards")
        XCTAssertNil(changes["Old page.md"], "A page the pack dropped stays when the reader changed it.")
        XCTAssertEqual(try text("Old page.md"), "Kept, as I wrote it.")
        XCTAssertEqual(changes[".obsidian/types.json"], .keptReadersSetting)
        XCTAssertEqual(try text(".obsidian/types.json"), "{\"mine\": \"text\"}")
        XCTAssertFalse(FileManager.default.fileExists(atPath: copyFolder.appendingPathComponent(".obsidian/types (Guide update).json").path))
    }

    func testANoteTheReaderDeletedIsNotBroughtBackAndTheReadersOwnNotesStay() throws {
        try FileManager.default.removeItem(at: copyFolder.appendingPathComponent("1 New to files/Backups.md"))
        try FileManager.default.removeItem(at: copyFolder.appendingPathComponent("Start here.md"))
        try Data("Mine.".utf8).write(to: copyFolder.appendingPathComponent("My note.md"))

        let changes = try update(previousFileNames: Set(earlierFiles.keys))

        XCTAssertNil(changes["1 New to files/Backups.md"])
        XCTAssertNil(changes["Start here.md"], "Deleted by the reader, even though the pack changed it.")
        XCTAssertFalse(FileManager.default.fileExists(atPath: copyFolder.appendingPathComponent("Start here.md").path))
        XCTAssertEqual(try text("My note.md"), "Mine.")
    }

    func testACopyMadeBeforeFileNamesWereRecordedGetsEveryMissingFile() throws {
        try FileManager.default.removeItem(at: copyFolder.appendingPathComponent("1 New to files/Backups.md"))
        let changes = try update(previousFileNames: nil)
        XCTAssertEqual(changes["1 New to files/Backups.md"], .added)
        XCTAssertEqual(changes["Start here.md"], .replaced, "An earlier pack's version, recognized without a record.")
    }

    func testRunningTheUpdateAgainChangesNothingAndReusesTheVersionBeside() throws {
        try Data("Changed.".utf8).write(to: copyFolder.appendingPathComponent("Start here.md"))
        _ = try update(previousFileNames: Set(earlierFiles.keys))
        let second = try update(previousFileNames: Set(newerFiles.keys))
        XCTAssertEqual(second, ["Start here.md": .keptWithNewVersionBeside(besidePath: "Start here (Guide update).md")])
        XCTAssertFalse(FileManager.default.fileExists(atPath: copyFolder.appendingPathComponent("Start here (Guide update 2).md").path))
    }

    func testTheSummaryNamesTheNewPagesTheUpdatedCountAndTheKeptChanges() {
        var changes: [String: GuideVaultCopyUpdate.Change] = [
            "6 Everyday examples/Signals and Sound/Week 1 - Sampling.md": .added,
            "6 Everyday examples/Signals and Sound/Signals and Sound.md": .added,
            "1 New to files/Moving in from Notion.md": .added,
            "1 New to files/What a vault is.md": .replaced,
            "Everyday examples.md": .replaced,
            "Start here.md": .keptWithNewVersionBeside(besidePath: "Start here (Guide update).md"),
            ".obsidian/types.json": .replaced,
            "Attachments/Cover.png": .added,
        ]
        XCTAssertEqual(GuideVaultUpdateSummary.text(for: changes),
                       "The Guide has new pages: Moving in from Notion, Signals and Sound and 1 more. 2 pages were updated. "
                       + "Your changes to Start here were kept; the Guide's new version is Start here (Guide update).")
        changes = [".obsidian/types.json": .replaced, "Attachments/Cover.png": .replaced]
        XCTAssertNil(GuideVaultUpdateSummary.text(for: changes), "Nothing the reader would notice.")
        XCTAssertEqual(GuideVaultUpdateSummary.text(for: ["Start here.md": .replaced]), "The Guide was updated. 1 page was updated.")
    }

    // MARK: - Helpers

    private func update(previousFileNames: Set<String>?) throws -> [String: GuideVaultCopyUpdate.Change] {
        let newerFolder = root.appendingPathComponent("newer", isDirectory: true)
        if !FileManager.default.fileExists(atPath: newerFolder.path) { _ = try write(newerFiles, into: "newer") }
        let newerPack = try Self.pack(of: newerFolder, revision: "newer")
        let currentHashes = Set(newerPack.files.map { file in file.name + file.sha256 })
        return try GuideVaultCopyUpdate(packFolder: newerFolder, copyFolder: copyFolder, files: newerPack.files,
                                        earlierFiles: earlierPack.files.filter { file in !currentHashes.contains(file.name + file.sha256) },
                                        previousFileNames: previousFileNames).apply()
    }

    private func write(_ files: [String: String], into folderName: String) throws -> URL {
        let folder = root.appendingPathComponent(folderName, isDirectory: true)
        for (name, contents) in files {
            let location = folder.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: location)
        }
        return folder
    }

    private func text(_ name: String) throws -> String {
        try String(contentsOf: copyFolder.appendingPathComponent(name), encoding: .utf8)
    }

    /// A pack of every file in `folder` but the pack's marker, named by its path inside it.
    static func pack(of folder: URL, revision: String) throws -> AddOnPack {
        let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey])
        var files: [AddOnFile] = []
        while let location = enumerator?.nextObject() as? URL {
            guard try location.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true,
                  location.lastPathComponent != GuideVaultCopy.packMarkerFileName else { continue }
            let data = try Data(contentsOf: location)
            let name = String(location.standardizedFileURL.path.dropFirst(folder.standardizedFileURL.path.count + 1))
            files.append(AddOnFile(name: name, byteCount: Int64(data.count), sha256: SHA256.hash(data: data).map { byte in String(format: "%02x", byte) }.joined()))
        }
        return AddOnPack(id: "graphite-guide-vault", title: "Graphite Guide Vault", revision: revision,
                         baseAddress: try XCTUnwrap(URL(string: "https://example.invalid/guide")), files: files)
    }
}
