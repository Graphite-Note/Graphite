/**
 * File: ReleaseVaultContentsTests.swift
 * -------------------------------------
 * Layer: Tests
 * Description: The release test vault stays what Docs/Release-test-vault-todo.md asks: small, silent, naming only
 *              known web pages, listed in its README, with its drawings still Graphite drawings.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

import XCTest
import GraphiteCore
import GraphiteFixtures

/// The rules of `Tests/ReleaseVault`, checked on every run of the suite (the pass over it runs only before a release,
/// `ReleaseVaultPass`): under 10 MB, no audio or video file so nothing in it can play a sound, every web address an
/// https page of a few known sites, every file listed in its README, settings included, and its drawings carrying their
/// strokes.
///
/// The web rule was "every address on the loopback placeholder" until 2026-11-12, when the owner asked for frames of real
/// pages for a person browsing the vault. Nothing in a test reaches those sites: the pass points every frame of its copy
/// at its own loopback server, whatever the address (`ReleaseVaultPassTests.testEveryWebFrameOfTheVaultIsPointedAtThePassServer`
/// checks it on every run), and links are not followed. What stays checked here is that the vault names only pages
/// that play nothing by themselves, over https.
final class ReleaseVaultContentsTests: XCTestCase {
    static let maximumVaultBytes = 10 * 1_048_576
    /// The sites the vault's notes may name: pages of text, with nothing that plays by itself.
    static let allowedWebHosts: Set<String> = ["example.com", "example.org", "en.wikipedia.org"]

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

    func testTheVaultIsUnderTenMegabytesAndHasNoAudioOrVideoFile() throws {
        let files = try vaultFiles(includingHidden: true)
        let totalBytes = try files.reduce(0) { total, file in total + (try file.location.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }
        XCTAssertLessThan(totalBytes, Self.maximumVaultBytes)
        let playableFiles = files.filter { file in DocumentKind(fileExtension: file.location.pathExtension) == .media }
        XCTAssertEqual(playableFiles.map(\.relativePath), [], "Nothing in the vault may play a sound.")
    }

    func testEveryWebAddressInTheNotesIsAnHTTPSPageOfAKnownSite() throws {
        let addressPattern = try NSRegularExpression(pattern: #"https?://[^\s"'`<>)\]]+"#, options: [.caseInsensitive])
        var addressCount = 0
        for file in try vaultFiles() where ["md", "canvas", "base"].contains(file.location.pathExtension) {
            let note = try String(contentsOf: file.location, encoding: .utf8)
            for match in addressPattern.matches(in: note, range: NSRange(location: 0, length: (note as NSString).length)) {
                let address = try XCTUnwrap(URL(string: (note as NSString).substring(with: match.range)))
                addressCount += 1
                XCTAssertEqual(address.scheme, "https", "\(file.relativePath) names \(address).")
                XCTAssertTrue(Self.allowedWebHosts.contains(address.host() ?? ""), "\(file.relativePath) names \(address).")
                XCTAssertFalse(["mp3", "mp4", "m4a", "mov", "webm", "wav"].contains(address.pathExtension.lowercased()), "\(address) could play.")
            }
        }
        XCTAssertGreaterThan(addressCount, 3, "The frames and links name real pages.")
    }

    func testTheReadmeListsEveryFileOfTheVault() throws {
        let readme = try String(contentsOf: FixtureFolders.releaseVault.appendingPathComponent("README.md"), encoding: .utf8)
        let unlisted = try vaultFiles(includingHidden: true).map(\.relativePath).filter { path in
            path != "README.md" && !path.hasSuffix(".DS_Store") && !readme.contains(path)
        }
        XCTAssertEqual(unlisted, [], "A file added to the vault gets a line in its README.md.")
    }

    func testTheDrawingsStillCarryTheirStrokes() throws {
        for path in ["Drawings/Circuit drawing.png", "Drawings/Every tool.png", "Drawings/Without paper.png"] {
            let drawing = try Data(contentsOf: FixtureFolders.releaseVault.appendingPathComponent(path))
            XCTAssertNotNil(try GraphitePNG.decode(drawing).drawing, "\(path): made again with scripts/make-release-vault.py --graphite-files.")
        }
    }
}
