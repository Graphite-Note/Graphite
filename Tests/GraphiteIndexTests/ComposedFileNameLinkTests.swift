/**
 * File: ComposedFileNameLinkTests.swift
 * -------------------------------------
 * Layer: Tests
 * Description: Links reach notes with accented names, both those Graphite writes composed and those an older
 *              Graphite or another app left decomposed on disk, indexed from a real temporary vault.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 28/11/2026
 */

import XCTest
import GraphiteCore
@testable import GraphiteIndex
import GraphiteTestSupport

final class ComposedFileNameLinkTests: XCTestCase {
    func testLinksInEitherSpellingReachANoteGraphiteWroteRenamedAndMoved() async throws {
        let vault = try TemporaryVault.make(for: self).root
        let store = VaultStore(root: vault)
        let index = try VaultIndex(databaseURL: vault.appendingPathExtension("cache").appendingPathComponent("index.sqlite"))
        let source = try VaultPath("Index.md")
        _ = try await store.save(Data("[[Caf\u{E9}]] [[Cafe\u{301}]] [[Cr\u{E8}me]]".utf8), at: source, expecting: .absent)
        let note = try VaultPath("Caf\u{E9}.md")
        _ = try await store.save(Data("# Café".utf8), at: note, expecting: .absent)
        _ = try await index.reconcile(root: vault)
        let composedResolution = try await index.resolve("Caf\u{E9}", from: source)
        XCTAssertEqual(composedResolution, [note])
        let decomposedResolution = try await index.resolve("Cafe\u{301}", from: source)
        XCTAssertEqual(decomposedResolution, [note])
        let backlinks = try await index.backlinks(to: note)
        XCTAssertEqual(backlinks, [source])

        let folder = try await store.createFolder(named: "\u{C9}tudes", in: .root)
        let moved = try folder.appending("Cr\u{E8}me.md")
        try await store.move(note, to: moved)
        _ = try await index.reconcile(root: vault)
        let movedResolution = try await index.resolve("Cr\u{E8}me", from: source)
        XCTAssertEqual(movedResolution, [moved])
        let fileCount = try await index.fileCount()
        XCTAssertEqual(fileCount, 2, "One file under one path, not one per spelling.")
    }

    func testAVaultWhoseNamesAreDecomposedOnDiskKeepsItsLinks() async throws {
        let vault = try TemporaryVault.make(for: self).root
        let index = try VaultIndex(databaseURL: vault.appendingPathExtension("cache").appendingPathComponent("index.sqlite"))
        try FileManager.default.createDirectory(at: vault.appendingPathComponent("Places"), withIntermediateDirectories: true)
        // Written through file URLs, as Graphite did before: the folder and the note are decomposed on disk.
        try FileManager.default.createDirectory(at: vault.appendingPathComponent("\u{C9}tudes"), withIntermediateDirectories: true)
        try Data("Café".utf8).write(to: vault.appendingPathComponent("\u{C9}tudes/Caf\u{E9} de Chavannes.md"))
        try Data("[[Caf\u{E9} de Chavannes]]".utf8).write(to: vault.appendingPathComponent("Places/Source.md"))
        let namesOnDisk = try FileManager.default.contentsOfDirectory(atPath: vault.appendingPathComponent("\u{C9}tudes").path)
        XCTAssertEqual(namesOnDisk.map { name in Array(name.utf8) }, [Array("Cafe\u{301} de Chavannes.md".utf8)], "The fixture is decomposed on disk.")

        _ = try await index.reconcile(root: vault)
        let source = try VaultPath("Places/Source.md")
        let note = try VaultPath("\u{C9}tudes/Caf\u{E9} de Chavannes.md")
        let resolution = try await index.resolve("Caf\u{E9} de Chavannes", from: source)
        XCTAssertEqual(resolution, [note], "The index keeps the composed path of a decomposed name.")
        let backlinks = try await index.backlinks(to: note)
        XCTAssertEqual(backlinks, [source])
        let snapshot = try await VaultStore(root: vault).read(note)
        XCTAssertEqual(String(decoding: snapshot.data, as: UTF8.self), "Café", "The composed path opens the decomposed file.")
    }
}
