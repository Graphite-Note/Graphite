/**
 * File: ReleaseVaultContentsTests.swift
 * -------------------------------------
 * Layer: Tests
 * Description: The release test vault stays what Docs/Release-test-vault-todo.md asks: small, silent, offline, listed
 *              in its README, with its drawing still a Graphite drawing.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

import XCTest
import GraphiteCore
import GraphiteFixtures

/// The rules of `Tests/ReleaseVault`, checked on every run of the suite (the pass over it runs only before a release,
/// `ReleaseVaultPass`): under 5 MB, no audio or video file so nothing in it can play a sound, every web address on the
/// loopback placeholder so nothing reaches the internet, every file listed in its README, and its drawing carrying its
/// strokes.
final class ReleaseVaultContentsTests: XCTestCase {
    static let maximumVaultBytes = 5 * 1_048_576
    /// The only web address the vault's notes may name; the pass points it at its own loopback server.
    static let placeholderAddress = "http://127.0.0.1:9/"

    private func vaultFiles(includingHidden: Bool = false) throws -> [(relativePath: String, location: URL)] {
        let root = FixtureFolders.releaseVault.standardizedFileURL
        let options: FileManager.DirectoryEnumerationOptions = includingHidden ? [] : [.skipsHiddenFiles]
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: options)
        var files: [(relativePath: String, location: URL)] = []
        while let location = enumerator?.nextObject() as? URL {
            guard try location.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            files.append((String(location.standardizedFileURL.path.dropFirst(root.path.count + 1)), location))
        }
        XCTAssertGreaterThan(files.count, 50, "The vault is in the repository.")
        return files
    }

    func testTheVaultIsUnderFiveMegabytesAndHasNoAudioOrVideoFile() throws {
        let files = try vaultFiles(includingHidden: true)
        let totalBytes = try files.reduce(0) { total, file in total + (try file.location.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }
        XCTAssertLessThan(totalBytes, Self.maximumVaultBytes)
        let playableFiles = files.filter { file in DocumentKind(fileExtension: file.location.pathExtension) == .media }
        XCTAssertEqual(playableFiles.map(\.relativePath), [], "Nothing in the vault may play a sound.")
    }

    func testEveryWebAddressInTheNotesIsTheLoopbackPlaceholder() throws {
        let addressPattern = try NSRegularExpression(pattern: #"https?://[^\s"'<>)\]]+"#)
        for file in try vaultFiles() where file.location.pathExtension == "md" {
            let note = try String(contentsOf: file.location, encoding: .utf8)
            for match in addressPattern.matches(in: note, range: NSRange(location: 0, length: (note as NSString).length)) {
                let address = (note as NSString).substring(with: match.range)
                XCTAssertTrue(address.hasPrefix(Self.placeholderAddress), "\(file.relativePath) names \(address).")
            }
        }
    }

    func testTheReadmeListsEveryFileOfTheVault() throws {
        let readme = try String(contentsOf: FixtureFolders.releaseVault.appendingPathComponent("README.md"), encoding: .utf8)
        let unlisted = try vaultFiles().map(\.relativePath).filter { path in path != "README.md" && !readme.contains(path) }
        XCTAssertEqual(unlisted, [], "A file added to the vault gets a line in its README.md.")
    }

    func testTheDrawingStillCarriesItsStrokes() throws {
        let drawing = try Data(contentsOf: FixtureFolders.releaseVault.appendingPathComponent("Drawings/Circuit drawing.png"))
        XCTAssertNotNil(try GraphitePNG.decode(drawing).drawing, "Made again with scripts/make-release-vault.py --graphite-files.")
    }
}
