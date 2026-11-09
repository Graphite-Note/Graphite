/**
 * File: LibraryDropReaderTests.swift
 * ----------------------------------
 * Layer: Tests
 * Description: What a drop on the library reads: an item dragged inside Graphite, files from another app with their
 *              names, and a file the Finder drags.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 04/11/2026
 */
import XCTest
import UniformTypeIdentifiers
import GraphiteCore
import GraphiteApple
@testable import GraphiteUI
import GraphiteTestSupport

@MainActor
final class LibraryDropReaderTests: XCTestCase {
    private var sourceFolder: URL!

    override func setUp() async throws {
        sourceFolder = try TemporaryVault.make(prefix: "LibraryDropReader", for: self).root
    }

    private func file(named name: String, contents: String = "hello") throws -> URL {
        let location = sourceFolder.appendingPathComponent(name)
        try Data(contents.utf8).write(to: location)
        return location
    }

    private func vaultItemProvider(path: String) throws -> NSItemProvider {
        let encoded = try JSONEncoder().encode(VaultItemTransfer(path: path, fileLocation: URL(fileURLWithPath: "/tmp/" + path)))
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.graphiteVaultItem.identifier, visibility: .all) { completion in
            completion(encoded, nil)
            return nil
        }
        return provider
    }

    func testAnItemDraggedInsideGraphiteIsAVaultItem() async throws {
        let providers = [try vaultItemProvider(path: "Course/A.md")]
        XCTAssertTrue(LibraryDropReader.canRead(providers))
        let sources = await LibraryDropReader.read(providers)
        XCTAssertEqual(sources, [.vaultItem("Course/A.md")])
    }

    func testTheFileLocationIsNotPartOfWhatAnotherGraphiteWindowReceives() throws {
        let encoded = try JSONEncoder().encode(VaultItemTransfer(path: "A.md", fileLocation: URL(fileURLWithPath: "/tmp/A.md")))
        XCTAssertEqual(try JSONSerialization.jsonObject(with: encoded) as? [String: String], ["path": "A.md"])
        XCTAssertNil(try JSONDecoder().decode(VaultItemTransfer.self, from: encoded).fileLocation)
    }

    func testFilesOfEveryKindFromAnotherAppArriveAsFilesWithTheirNames() async throws {
        for fileName in ["Notes.txt", "Slides.pdf", "Board.jpeg", "Board.png", "Lecture.mp4", "Data.csv", "Archive.zip"] {
            let provider = try XCTUnwrap(NSItemProvider(contentsOf: try file(named: fileName)), fileName)
            XCTAssertTrue(LibraryDropReader.canRead([provider]), fileName)
            let sources = await LibraryDropReader.read([provider])
            guard sources.count == 1, case .file(let dropped) = sources[0] else { return XCTFail("\(fileName) arrives as one file, not \(sources).") }
            XCTAssertEqual(dropped.location.pathExtension, (fileName as NSString).pathExtension, fileName)
            XCTAssertFalse(dropped.location.lastPathComponent.hasPrefix("."), fileName)
            XCTAssertEqual(try String(contentsOf: dropped.location, encoding: .utf8), "hello", fileName)
            DroppedFileBatch(files: [dropped]).discard()
        }
    }

    func testAFileTheFinderDragsIsTakenInPlaceByItsAddress() async throws {
        let original = try file(named: "Report.pdf")
        let provider = NSItemProvider(object: original as NSURL)
        let sources = await LibraryDropReader.read([provider])
        XCTAssertEqual(sources, [.file(DroppedFile(location: original, stagingFolder: nil))])
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
    }

    /// Photos offers a photo as HEIC and as JPEG; Obsidian shows no HEIC, so the JPEG is taken,
    /// whichever the app lists first. A HEIC file alone (from Files) stays HEIC.
    func testAPhotoOfferedAsHEICAndJPEGIsTakenAsJPEG() throws {
        let photo = NSItemProvider()
        for type in [UTType.heic, .jpeg] {
            photo.registerDataRepresentation(forTypeIdentifier: type.identifier, visibility: .all) { completion in
                completion(Data("photo".utf8), nil)
                return nil
            }
        }
        XCTAssertEqual(LibraryDropReader.importableType(of: photo), .jpeg)
        let heicFile = NSItemProvider()
        heicFile.registerDataRepresentation(forTypeIdentifier: UTType.heic.identifier, visibility: .all) { completion in
            completion(Data("photo".utf8), nil)
            return nil
        }
        XCTAssertEqual(LibraryDropReader.importableType(of: heicFile), .heic)
    }

    /// An app's own file type that declares no conformance (a campus or messaging app's
    /// document) is a file when the app names it, and arrives under that name.
    func testAFileOfAnAppsOwnTypeArrivesUnderItsName() async throws {
        let folder: URL = sourceFolder
        let provider = NSItemProvider()
        provider.registerFileRepresentation(forTypeIdentifier: "com.example.campus.timetable", fileOptions: [], visibility: .all) { completion in
            let location = folder.appendingPathComponent("timetable-\(UUID().uuidString)")
            try? Data("hello".utf8).write(to: location)
            completion(location, false, nil)
            return nil
        }
        provider.suggestedName = "Timetable.campus"
        XCTAssertTrue(LibraryDropReader.canRead([provider]))
        let sources = await LibraryDropReader.read([provider])
        guard sources.count == 1, case .file(let dropped) = sources[0] else { return XCTFail("One file arrives, not \(sources).") }
        XCTAssertEqual(dropped.location.lastPathComponent, "Timetable.campus")
        XCTAssertEqual(try String(contentsOf: dropped.location, encoding: .utf8), "hello")
        DroppedFileBatch(files: [dropped]).discard()
    }

    func testAWebAddressCreatesNothing() async throws {
        let provider = NSItemProvider(object: URL(string: "https://example.com/page")! as NSURL)
        XCTAssertFalse(LibraryDropReader.canRead([provider]))
        let sources = await LibraryDropReader.read([provider])
        XCTAssertEqual(sources, [])
    }

    func testASelectionOfTextCreatesNothing() async throws {
        let provider = NSItemProvider(object: "Some selected words" as NSString)
        XCTAssertFalse(LibraryDropReader.canRead([provider]))
        let sources = await LibraryDropReader.read([provider])
        XCTAssertEqual(sources, [])
    }
}
