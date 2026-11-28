/**
 * File: ComposedFileNamesTests.swift
 * ----------------------------------
 * Layer: Tests
 * Description: The names Graphite writes in the vault are in Unicode's composed form (NFC) on disk, byte for byte:
 *              saved, renamed, moved, duplicated and appended files and new folders, on a real temporary vault.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 28/11/2026
 */

import XCTest
@testable import GraphiteCore
import GraphiteTestSupport

final class ComposedFileNamesTests: XCTestCase {
    /// The names in `folder` as the file system stores them, hidden ones left out. Swift keeps
    /// a string's UTF-8 as the system hands it over, so the bytes are the ones on disk.
    private func namesOnDisk(in folder: URL) throws -> Set<[UInt8]> {
        Set(try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { name in !name.hasPrefix(".") }.map { name in Array(name.utf8) })
    }

    private func composedBytes(_ names: String...) -> Set<[UInt8]> {
        Set(names.map { name in Array(name.precomposedStringWithCanonicalMapping.utf8) })
    }

    /// Makes an empty file at `relativePath` with the bytes of the name as given, as another app may.
    private func makeFileKeepingBytes(_ relativePath: String, in vault: URL) throws {
        let descriptor = open(vault.path + "/" + relativePath, O_WRONLY | O_CREAT | O_EXCL, 0o644)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        close(descriptor)
    }

    func testSavedRenamedAndMovedNotesHaveComposedNamesOnDisk() async throws {
        let vault = try TemporaryVault.make(for: self).root
        let store = VaultStore(root: vault)
        let note = try VaultPath("Caf\u{E9}.md")
        _ = try await store.save(Data("# Café".utf8), at: note, expecting: .absent)
        var names = try namesOnDisk(in: vault)
        XCTAssertEqual(names, composedBytes("Caf\u{E9}.md"), "A new note's name is written composed.")
        XCTAssertNotEqual(Array("Caf\u{E9}.md".utf8), Array("Cafe\u{301}.md".utf8), "The two spellings differ in bytes.")

        let renamed = try VaultPath("Cr\u{E8}me br\u{FB}l\u{E9}e.md")
        try await store.move(note, to: renamed)
        names = try namesOnDisk(in: vault)
        XCTAssertEqual(names, composedBytes("Cr\u{E8}me br\u{FB}l\u{E9}e.md"), "A renamed note's new name is written composed.")

        let folder = try await store.createFolder(named: "\u{C9}tudes", in: .root)
        let nestedFolder = try folder.appending("Ann\u{E9}e 1")
        try await store.createDirectory(nestedFolder)
        let moved = try nestedFolder.appending("Cr\u{E8}me br\u{FB}l\u{E9}e.md")
        try await store.move(renamed, to: moved)
        names = try namesOnDisk(in: vault)
        XCTAssertEqual(names, composedBytes("\u{C9}tudes"), "A new folder's name is written composed, and the note left the root.")
        names = try namesOnDisk(in: vault.appendingPathComponent("\u{C9}tudes"))
        XCTAssertEqual(names, composedBytes("Ann\u{E9}e 1"), "A folder made inside a new folder is composed too.")
        names = try namesOnDisk(in: vault.appendingPathComponent("\u{C9}tudes/Ann\u{E9}e 1"))
        XCTAssertEqual(names, composedBytes("Cr\u{E8}me br\u{FB}l\u{E9}e.md"), "A moved note keeps its composed name.")

        let snapshot = try await store.read(moved)
        XCTAssertEqual(String(decoding: snapshot.data, as: UTF8.self), "# Café")
    }

    func testMovingANoteWrittenDecomposedGivesItTheComposedNameAndNeverReplacesAnother() async throws {
        let vault = try TemporaryVault.make(for: self).root
        let store = VaultStore(root: vault)
        try makeFileKeepingBytes("Cafe\u{301}.md", in: vault)
        try makeFileKeepingBytes("Other.md", in: vault)
        try await store.move(try VaultPath("Cafe\u{301}.md"), to: try VaultPath("Caf\u{E9} 2.md"))
        XCTAssertEqual(try namesOnDisk(in: vault), composedBytes("Caf\u{E9} 2.md", "Other.md"))

        var refusal: (any Error)?
        do { try await store.move(try VaultPath("Caf\u{E9} 2.md"), to: try VaultPath("Other.md")) } catch { refusal = error }
        XCTAssertNotNil(refusal, "A move never replaces another file.")
        try await store.move(try VaultPath("Other.md"), to: try VaultPath("OTHER.md"))
        XCTAssertEqual(try namesOnDisk(in: vault), composedBytes("Caf\u{E9} 2.md", "OTHER.md"), "A change of capitals alone is a rename of the same file.")
    }

    func testSavingANoteWrittenDecomposedKeepsItsNameOnDisk() async throws {
        let vault = try TemporaryVault.make(for: self).root
        let store = VaultStore(root: vault)
        try makeFileKeepingBytes("Cafe\u{301}.md", in: vault)
        let note = try VaultPath("Cafe\u{301}.md")
        XCTAssertEqual(note.rawValue, "Caf\u{E9}.md", "A vault path is composed whatever form it came in.")
        let snapshot = try await store.read(note)
        _ = try await store.save(Data("edited".utf8), at: note, expecting: .revision(snapshot.revision))
        XCTAssertEqual(try namesOnDisk(in: vault), [Array("Cafe\u{301}.md".utf8)], "Replacing a file keeps the name it has: an old vault is not renamed behind its back.")
    }

    func testDuplicatesAndAppendedFilesHaveComposedNames() async throws {
        let vault = try TemporaryVault.make(for: self).root
        let store = VaultStore(root: vault)
        let folder = try await store.createFolder(named: "\u{C9}tudes", in: .root)
        _ = try await store.save(Data("x".utf8), at: try folder.appending("Caf\u{E9}.md"), expecting: .absent)
        let folderCopy = try await store.duplicate(folder)
        XCTAssertEqual(folderCopy.rawValue, "\u{C9}tudes 1")
        XCTAssertEqual(try namesOnDisk(in: vault), composedBytes("\u{C9}tudes", "\u{C9}tudes 1"), "A duplicated folder's name is composed.")
        XCTAssertEqual(try namesOnDisk(in: vault.appendingPathComponent("\u{C9}tudes 1")), composedBytes("Caf\u{E9}.md"), "Its contents keep their names.")

        let noteCopy = try await store.duplicate(try folder.appending("Caf\u{E9}.md"))
        XCTAssertEqual(noteCopy.rawValue, "\u{C9}tudes/Caf\u{E9} 1.md")
        XCTAssertEqual(try namesOnDisk(in: vault.appendingPathComponent("\u{C9}tudes")), composedBytes("Caf\u{E9}.md", "Caf\u{E9} 1.md"))

        try await store.append(Data("line\n".utf8), at: try VaultPath("Journal d\u{2019}\u{E9}t\u{E9}.md"))
        XCTAssertTrue(try namesOnDisk(in: vault).contains(Array("Journal d\u{2019}\u{E9}t\u{E9}.md".utf8)), "A file made by an append is composed.")
    }

    func testCreatingFoldersMakesEveryMissingOneComposedAndRefusesAFile() throws {
        let vault = try TemporaryVault.make(for: self).root
        let deepFolder = vault.appendingPathComponent("\u{C0} faire/\u{C9}t\u{E9}/No\u{EB}l")
        try ComposedFileNames.createDirectory(at: deepFolder)
        try ComposedFileNames.createDirectory(at: deepFolder)
        XCTAssertEqual(try namesOnDisk(in: vault), composedBytes("\u{C0} faire"))
        XCTAssertEqual(try namesOnDisk(in: vault.appendingPathComponent("\u{C0} faire/\u{C9}t\u{E9}")), composedBytes("No\u{EB}l"))

        try ComposedFileNames.createEmptyFile(at: vault.appendingPathComponent("R\u{E9}sum\u{E9}"))
        XCTAssertThrowsError(try ComposedFileNames.createDirectory(at: vault.appendingPathComponent("R\u{E9}sum\u{E9}")), "A file of the name is not a folder.")
        XCTAssertThrowsError(try ComposedFileNames.createEmptyFile(at: vault.appendingPathComponent("Re\u{301}sume\u{301}")), "The other spelling names the same file.")
    }
}
