/**
 * File: ZipArchiveUnpackingTests.swift
 * ------------------------------------
 * Layer: Tests
 * Description: Unpacking a ZIP archive opened in Graphite: folders kept, names that leave the folder refused, the size
 *              and count limits, what the Finder adds skipped, a Goodnotes notebook inside read as a notebook, and an
 *              archive made by the Mac's own Compress; and the copy an opened file gets, with iOS's Inbox cleared.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 13/11/2026
 */

import XCTest
import NotebookImport
@testable import GraphiteApple
import GraphiteFixtures
import GraphiteTestSupport

final class ZipArchiveUnpackingTests: XCTestCase {
    private var workFolder: URL!

    override func setUpWithError() throws {
        workFolder = try TemporaryVault.make(prefix: "ZipArchiveUnpacking", for: self).root
    }

    private func archive(_ entries: [(name: String, contents: Data)], named name: String = "Archive.zip") throws -> URL {
        let location = workFolder.appendingPathComponent(name)
        try StoredZipArchive.write(entries, to: location)
        return location
    }

    private func emptyFolder(_ name: String = "Unpacked") throws -> URL {
        let folder = workFolder.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func text(_ string: String) -> Data { Data(string.utf8) }

    // MARK: Folders

    func testNestedFoldersAreKeptAndEachFileHoldsItsBytes() throws {
        let source = try archive([("Courses/", Data()), ("Courses/Physics/Waves.md", text("# Waves")),
                                  ("Courses/Physics/Lab/Notes.txt", text("lab")), ("Top.md", text("top"))])
        let unpacked = try ZipArchiveUnpacking.unpack(source, into: try emptyFolder())

        XCTAssertEqual(unpacked.files.map(\.pathComponents), [["Courses", "Physics", "Waves.md"], ["Courses", "Physics", "Lab", "Notes.txt"], ["Top.md"]])
        XCTAssertEqual(try String(contentsOf: unpacked.folder.appendingPathComponent("Courses/Physics/Lab/Notes.txt"), encoding: .utf8), "lab")
        XCTAssertEqual(unpacked.files.map(\.location), unpacked.files.map { file in
            file.pathComponents.reduce(unpacked.folder) { partial, component in partial.appendingPathComponent(component) }
        })
        XCTAssertEqual(unpacked.leftOutEntries, [])
    }

    func testWindowsBackslashesSeparateFolders() throws {
        let unpacked = try ZipArchiveUnpacking.unpack(try archive([("Export\\Lecture.md", text("x"))]), into: try emptyFolder())
        XCTAssertEqual(unpacked.files.map(\.pathComponents), [["Export", "Lecture.md"]])
    }

    func testOfTwoEntriesWithOneNameTheLaterIsWritten() throws {
        let unpacked = try ZipArchiveUnpacking.unpack(try archive([("Same.md", text("first")), ("Same.md", text("second"))]), into: try emptyFolder())
        XCTAssertEqual(unpacked.files.count, 1)
        XCTAssertEqual(try String(contentsOf: unpacked.folder.appendingPathComponent("Same.md"), encoding: .utf8), "second")
    }

    // MARK: Names that leave the folder

    func testNamesThatClimbOutOfTheFolderOrAreAbsoluteAreRefusedAndNothingIsWrittenOutside() throws {
        let hostile = ["../outside.md", "Courses/../../outside.md", "/absolute.md", "C:\\Windows\\outside.md", "..\\outside.md"]
        let source = try archive(hostile.map { name in (name, text("x")) } + [("Kept.md", text("kept"))])
        let unpacked = try ZipArchiveUnpacking.unpack(source, into: try emptyFolder())

        XCTAssertEqual(unpacked.files.map(\.pathComponents), [["Kept.md"]])
        XCTAssertEqual(unpacked.leftOutEntries, hostile.map { name in UnpackedArchive.LeftOutEntry(name: name, reason: .pathOutsideArchive) })
        XCTAssertFalse(FileManager.default.fileExists(atPath: workFolder.appendingPathComponent("outside.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: workFolder.deletingLastPathComponent().appendingPathComponent("outside.md").path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: workFolder.path).sorted(), ["Archive.zip", "Unpacked"])
    }

    func testEntryPlacements() {
        XCTAssertEqual(ArchiveEntryPath.placement(ofEntryNamed: "a/./b.md"), .file(["a", "b.md"]))
        XCTAssertEqual(ArchiveEntryPath.placement(ofEntryNamed: "a//b.md"), .file(["a", "b.md"]))
        XCTAssertEqual(ArchiveEntryPath.placement(ofEntryNamed: "a/b/"), .folder)
        XCTAssertEqual(ArchiveEntryPath.placement(ofEntryNamed: ""), .refused)
        XCTAssertEqual(ArchiveEntryPath.placement(ofEntryNamed: "a/..b.md"), .skipped, "A name starting with a dot is hidden, not a climb.")
        XCTAssertEqual(ArchiveEntryPath.placement(ofEntryNamed: "a/b..md"), .file(["a", "b..md"]))
        XCTAssertEqual(ArchiveEntryPath.placement(ofEntryNamed: "a\0b.md"), .refused)
    }

    // MARK: What the Finder and Windows add

    func testResourceForksAndHiddenAndSystemFilesAreSkippedSilently() throws {
        let source = try archive([("Notes/A.md", text("a")), ("__MACOSX/Notes/._A.md", text("fork")), ("Notes/.DS_Store", text("ds")),
                                  ("Notes/Thumbs.db", text("thumbs")), (".hidden/secret.md", text("s"))])
        let unpacked = try ZipArchiveUnpacking.unpack(source, into: try emptyFolder())

        XCTAssertEqual(unpacked.files.map(\.pathComponents), [["Notes", "A.md"]])
        XCTAssertEqual(unpacked.leftOutEntries, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: unpacked.folder.appendingPathComponent("__MACOSX").path))
    }

    // MARK: Limits

    func testAnArchiveDeclaringMoreBytesThanTheLimitIsRefusedBeforeAnythingIsWritten() throws {
        let source = try archive([("One.md", Data(count: 600)), ("Two.md", Data(count: 600))])
        let folder = try emptyFolder()
        let limits = ArchiveUnpackingLimits(maximumFileCount: 10, maximumTotalBytes: 1_000, entryLimits: .standard)

        XCTAssertThrowsError(try ZipArchiveUnpacking.unpack(source, into: folder, limits: limits)) { error in
            XCTAssertEqual(error as? ArchiveUnpackingFailure, .tooLarge(byteCount: 1_200, limitBytes: 1_000))
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), [])
    }

    func testAnArchiveOfMoreFilesThanTheLimitIsRefused() throws {
        let source = try archive((1...4).map { number in ("Note \(number).md", text("x")) })
        let limits = ArchiveUnpackingLimits(maximumFileCount: 3, maximumTotalBytes: 1_000, entryLimits: .standard)
        XCTAssertThrowsError(try ZipArchiveUnpacking.unpack(source, into: try emptyFolder(), limits: limits)) { error in
            XCTAssertEqual(error as? ArchiveUnpackingFailure, .tooManyFiles(count: 4, limit: 3))
        }
    }

    func testAnEntryOverItsOwnLimitIsLeftOutAndTheOthersAreUnpacked() throws {
        var entryLimits = NotebookImportLimits.standard
        entryLimits.maximumEntryBytes = 100
        let source = try archive([("Large.pdf", Data(count: 101)), ("Small.md", text("small"))])
        let limits = ArchiveUnpackingLimits(maximumFileCount: 10, maximumTotalBytes: 1_000, entryLimits: entryLimits)
        let unpacked = try ZipArchiveUnpacking.unpack(source, into: try emptyFolder(), limits: limits)

        XCTAssertEqual(unpacked.files.map(\.pathComponents), [["Small.md"]])
        XCTAssertEqual(unpacked.leftOutEntries, [UnpackedArchive.LeftOutEntry(name: "Large.pdf", reason: .tooLarge(limitBytes: 100))])
        XCTAssertFalse(FileManager.default.fileExists(atPath: unpacked.folder.appendingPathComponent("Large.pdf").path))
    }

    func testTheStandardLimitsAreFourEntriesWorth() {
        XCTAssertEqual(ArchiveUnpackingLimits.standard.maximumTotalBytes, 4 * NotebookImportLimits.standard.maximumEntryBytes)
        XCTAssertEqual(ArchiveUnpackingLimits.standard.maximumFileCount, 10_000)
    }

    // MARK: Damage

    func testAFileThatIsNotAZipArchiveIsRefusedByName() throws {
        let location = workFolder.appendingPathComponent("Fake.zip")
        try text("not an archive at all").write(to: location)
        XCTAssertThrowsError(try ZipArchiveUnpacking.unpack(location, into: try emptyFolder())) { error in
            XCTAssertEqual(error as? ArchiveUnpackingFailure, .notAZipArchive)
        }
        XCTAssertThrowsError(try ZipArchiveUnpacking.unpack(workFolder.appendingPathComponent("Missing.zip"), into: try emptyFolder("Other"))) { error in
            XCTAssertEqual(error as? ArchiveUnpackingFailure, .unreadable)
        }
    }

    func testAnEntryWhoseBytesDoNotMatchItsChecksumIsLeftOutAndRemoved() throws {
        var bytes = StoredZipArchive.bytes(of: [("Damaged.md", text("hello")), ("Fine.md", text("fine"))])
        // The first entry's data starts after its 30-byte local header and its 10-byte name.
        bytes[40] ^= 0xFF
        let location = workFolder.appendingPathComponent("Damaged.zip")
        try bytes.write(to: location)
        let unpacked = try ZipArchiveUnpacking.unpack(location, into: try emptyFolder())

        XCTAssertEqual(unpacked.files.map(\.pathComponents), [["Fine.md"]])
        XCTAssertEqual(unpacked.leftOutEntries, [UnpackedArchive.LeftOutEntry(name: "Damaged.md", reason: .damaged)])
        XCTAssertFalse(FileManager.default.fileExists(atPath: unpacked.folder.appendingPathComponent("Damaged.md").path))
    }

    func testAFileWhereAnotherEntryNeedsAFolderIsLeftOutAsTaken() throws {
        let unpacked = try ZipArchiveUnpacking.unpack(try archive([("Lecture", text("file")), ("Lecture/Notes.md", text("x"))]), into: try emptyFolder())
        XCTAssertEqual(unpacked.files.map(\.pathComponents), [["Lecture"]])
        XCTAssertEqual(unpacked.leftOutEntries, [UnpackedArchive.LeftOutEntry(name: "Lecture/Notes.md", reason: .nameTaken)])
    }

    // MARK: Notebooks inside

    func testAGoodnotesNotebookInsideAnArchiveIsUnpackedWholeAndOpensAsANotebook() throws {
        let notebook = FixtureFolders.syntheticNotebooks.appendingPathComponent("Synthetic lecture.goodnotes")
        let notebookBytes = try Data(contentsOf: notebook)
        let source = try archive([("Export/Synthetic lecture.goodnotes", notebookBytes)])
        let unpacked = try ZipArchiveUnpacking.unpack(source, into: try emptyFolder())

        let unpackedNotebook = try XCTUnwrap(unpacked.files.first?.location)
        XCTAssertEqual(try Data(contentsOf: unpackedNotebook), notebookBytes)
        let opened = try OpenedNotebook.open(unpackedNotebook, format: .goodnotes, limits: .standard)
        XCTAssertEqual(opened.sourcePageCount, 4)
    }

    #if os(macOS)
    /// The Finder's Compress (`ditto -c -k --keepParent`, as Archive Utility writes it): deflated entries, sizes after
    /// the data, and the `__MACOSX` folder of resource forks.
    func testAnArchiveMadeByTheFinderIsUnpackedWithItsFolders() throws {
        let folder = workFolder.appendingPathComponent("Lectures", isDirectory: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Week 1"), withIntermediateDirectories: true)
        try text(String(repeating: "Waves and optics. ", count: 400)).write(to: folder.appendingPathComponent("Week 1/Waves.md"))
        try text("Summary").write(to: folder.appendingPathComponent("Summary.txt"))
        let compressed = workFolder.appendingPathComponent("Lectures.zip")
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", folder.path, compressed.path]
        try ditto.run()
        ditto.waitUntilExit()
        XCTAssertEqual(ditto.terminationStatus, 0)

        let unpacked = try ZipArchiveUnpacking.unpack(compressed, into: try emptyFolder())
        XCTAssertEqual(Set(unpacked.files.map(\.pathComponents)), [["Lectures", "Week 1", "Waves.md"], ["Lectures", "Summary.txt"]])
        XCTAssertEqual(try String(contentsOf: unpacked.folder.appendingPathComponent("Lectures/Week 1/Waves.md"), encoding: .utf8),
                       String(repeating: "Waves and optics. ", count: 400))
        XCTAssertEqual(unpacked.leftOutEntries, [])
    }
    #endif
}

/// The copy a file opened from another app gets before its vault opens (`OpenedFileStaging`).
final class OpenedFileStagingTests: XCTestCase {
    private var workFolder: URL!

    override func setUpWithError() throws {
        workFolder = try TemporaryVault.make(prefix: "OpenedFileStaging", for: self).root
    }

    func testAnOriginalIsCopiedAndKept() throws {
        let original = workFolder.appendingPathComponent("Slides.pdf")
        try Data("pdf".utf8).write(to: original)
        let staged = try OpenedFileStaging.stage(original, inboxFolder: workFolder.appendingPathComponent("Inbox"))
        defer { DroppedFileStaging.discard([staged.folder]) }

        XCTAssertEqual(staged.copy.lastPathComponent, "Slides.pdf")
        XCTAssertEqual(try Data(contentsOf: staged.copy), Data("pdf".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
    }

    /// iOS copies a file another app shares into Documents/Inbox, which Files shows inside Graphite's folder beside the
    /// vaults: the handed-over copy goes once staged, and the Inbox with it when nothing else is in it.
    func testTheCopyIOSLeftInTheInboxIsRemovedWithTheEmptyInbox() throws {
        let inbox = workFolder.appendingPathComponent("Inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let handedOver = inbox.appendingPathComponent("Lecture.goodnotes")
        try Data("notebook".utf8).write(to: handedOver)
        let staged = try OpenedFileStaging.stage(handedOver, inboxFolder: inbox)
        defer { DroppedFileStaging.discard([staged.folder]) }

        XCTAssertEqual(try Data(contentsOf: staged.copy), Data("notebook".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: handedOver.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: inbox.path))
    }

    func testAFileThatCannotBeReadIsNotStaged() {
        XCTAssertThrowsError(try OpenedFileStaging.stage(workFolder.appendingPathComponent("Missing.pdf"), inboxFolder: nil))
    }

    func testInsideComparesWholeFolderNames() {
        let folder = URL(fileURLWithPath: "/tmp/Vault", isDirectory: true)
        XCTAssertTrue(OpenedFileStaging.isInside(URL(fileURLWithPath: "/tmp/Vault/Note.md"), folder: folder))
        XCTAssertFalse(OpenedFileStaging.isInside(URL(fileURLWithPath: "/tmp/Vault 2/Note.md"), folder: folder))
    }
}
