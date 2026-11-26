/**
 * File: GuideVaultTests.swift
 * ---------------------------
 * Layer: Tests
 * Description: The Graphite Guide vault stays what Docs/Guide-vault-todo.md asks, its pack lists it as it is, and the
 *              reader's copy is made once and again only when asked.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

import XCTest
import CryptoKit
import GraphiteCore
import GraphiteFixtures
import GraphiteTestSupport
@testable import GraphiteUI

/// The rules of `Guide/Graphite Guide`, checked on every run of the suite (the pass over it in every view runs before a
/// release, `GuideVaultPassTests`): under 5 MB, nothing that plays a sound, every link and embed found, the web pages it
/// names on https, a note for every Guide topic that names one, and `GuideVaultPack` listing every file as it is, so a
/// change to the vault is pinned again (`scripts/make-guide-vault.py --pack-revision`) before the Guide downloads it.
final class GuideVaultTests: XCTestCase {
    static let maximumVaultBytes = 5 * 1_048_576
    static let allowedWebHosts: Set<String> = ["en.wikipedia.org", "github.com"]
    /// A link to a note not written yet, on purpose: `5 Connecting notes/Links and backlinks.md` shows how following one
    /// makes the note.
    static let intendedUnresolvedLinks: Set<String> = ["Mushroom soup"]

    private func vaultFiles() throws -> [(relativePath: String, location: URL)] {
        let root = FixtureFolders.guideVault.standardizedFileURL
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey])
        var files: [(relativePath: String, location: URL)] = []
        while let location = enumerator?.nextObject() as? URL {
            guard try location.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true, location.lastPathComponent != ".DS_Store" else { continue }
            files.append((String(location.standardizedFileURL.path.dropFirst(root.path.count + 1)), location))
        }
        XCTAssertGreaterThan(files.count, 50, "The vault is in the repository.")
        return files.sorted { first, second in first.relativePath < second.relativePath }
    }

    func testTheVaultIsUnderFiveMegabytesAndHasNoAudioOrVideoFile() throws {
        let files = try vaultFiles()
        let totalBytes = try files.reduce(0) { total, file in total + (try file.location.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }
        XCTAssertLessThan(totalBytes, Self.maximumVaultBytes)
        XCTAssertEqual(files.filter { file in DocumentKind(fileExtension: file.location.pathExtension) == .media }.map(\.relativePath), [],
                       "Nothing in the guide may play a sound.")
    }

    func testEveryLinkAndEmbedFindsItsFile() throws {
        let files = try vaultFiles()
        var known = Set<String>()
        for file in files {
            let path = file.relativePath.lowercased(), name = (path as NSString).lastPathComponent
            known.formUnion([path, name])
            if path.hasSuffix(".md") { known.formUnion([String(path.dropLast(3)), String(name.dropLast(3))]) }
        }
        let linkPattern = try NSRegularExpression(pattern: #"\[\[([^\]]+)\]\]"#)
        var unresolved = Set<String>(), linkCount = 0
        for file in files where file.relativePath.hasSuffix(".md") && !file.relativePath.hasPrefix("Templates/") {
            let text = Self.withoutCode(try String(contentsOf: file.location, encoding: .utf8)) as NSString
            for match in linkPattern.matches(in: text as String, range: NSRange(location: 0, length: text.length)) {
                let target = text.substring(with: match.range(at: 1)).replacingOccurrences(of: "\\|", with: "|")
                let name = String(target.split(separator: "|", maxSplits: 1).first ?? "").split(separator: "#", maxSplits: 1).first.map(String.init) ?? ""
                linkCount += 1
                if !name.isEmpty, !known.contains(name.trimmingCharacters(in: .whitespaces).lowercased()) { unresolved.insert(name) }
            }
        }
        XCTAssertGreaterThan(linkCount, 200, "The notes link to each other.")
        XCTAssertEqual(unresolved, Self.intendedUnresolvedLinks)
    }

    func testEveryWebAddressIsAnHTTPSPageOfAKnownSite() throws {
        let addressPattern = try NSRegularExpression(pattern: #"https?://[^\s"'`<>)\]]+"#, options: [.caseInsensitive])
        for file in try vaultFiles() where ["md", "canvas", "base"].contains(file.location.pathExtension) {
            let note = try String(contentsOf: file.location, encoding: .utf8) as NSString
            for match in addressPattern.matches(in: note as String, range: NSRange(location: 0, length: note.length)) {
                let address = try XCTUnwrap(URL(string: note.substring(with: match.range)))
                XCTAssertEqual(address.scheme, "https", "\(file.relativePath) names \(address).")
                XCTAssertTrue(Self.allowedWebHosts.contains(address.host() ?? ""), "\(file.relativePath) names \(address).")
            }
        }
    }

    func testEveryGuideTopicThatNamesANoteFindsItInTheVault() {
        let topicsWithNotes = GuideTopic.allCases.filter { topic in topic.guideVaultNote != nil }
        XCTAssertGreaterThan(topicsWithNotes.count, 25)
        for topic in topicsWithNotes {
            let note = FixtureFolders.guideVault.appendingPathComponent((topic.guideVaultNote ?? "") + ".md")
            XCTAssertTrue(FileManager.default.fileExists(atPath: note.path), "\(topic): \(topic.guideVaultNote ?? "")")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: FixtureFolders.guideVault.appendingPathComponent(GuideVaultPack.startNote + ".md").path))
    }

    func testThePackListsEveryFileOfTheVaultAsItIs() throws {
        let listed = Dictionary(uniqueKeysWithValues: GuideVaultPack.files.map { file in (file.name, file) })
        var differences: [String] = []
        for file in try vaultFiles() {
            let data = try Data(contentsOf: file.location)
            let hash = SHA256.hash(data: data).map { byte in String(format: "%02x", byte) }.joined()
            if listed[file.relativePath] != AddOnFile(name: file.relativePath, byteCount: Int64(data.count), sha256: hash) {
                differences.append(file.relativePath)
            }
        }
        differences += Set(listed.keys).subtracting(try vaultFiles().map(\.relativePath)).sorted()
        XCTAssertEqual(differences, [], "Commit the vault, then run scripts/make-guide-vault.py --pack-revision <that commit>.")
        XCTAssertNotNil(GuideVaultPack.pack)
        XCTAssertEqual(GuideVaultPack.pack?.delivery, .downloadOnly, "A download, not part of the app (the lean-core rule).")
    }

    /// Fenced and inline code are syntax shown, not links.
    private static func withoutCode(_ text: String) -> String {
        let fences = text.replacingOccurrences(of: #"(?s)(`{3,}).*?\1"#, with: "", options: .regularExpression)
        return fences.replacingOccurrences(of: #"`[^`\n]*`"#, with: "", options: .regularExpression)
    }
}

/// The reader's copy of the guide in Graphite's Documents folder: made once, opened again, and made afresh beside the old
/// one only when asked, never over what the reader wrote.
final class GuideVaultCopyTests: XCTestCase {
    private var packFolder: URL!
    private var copy: GuideVaultCopy!

    override func setUpWithError() throws {
        let root = try TemporaryVault.make(prefix: "GuideVaultCopyTests", for: self).root
        packFolder = root.appendingPathComponent("Add-ons/graphite-guide-vault", isDirectory: true)
        try FileManager.default.createDirectory(at: packFolder.appendingPathComponent("1 New to files"), withIntermediateDirectories: true)
        try Data("# Welcome".utf8).write(to: packFolder.appendingPathComponent("Start here.md"))
        try Data("A folder.".utf8).write(to: packFolder.appendingPathComponent("1 New to files/What a vault is.md"))
        try Data("abc123".utf8).write(to: packFolder.appendingPathComponent(GuideVaultCopy.packMarkerFileName))
        let suiteName = "GuideVaultCopyTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        copy = GuideVaultCopy(documentsFolder: root.appendingPathComponent("Documents", isDirectory: true), defaults: defaults)
    }

    func testTheFirstCopyIsMadeOnceWithoutThePacksMarker() throws {
        XCTAssertNil(copy.existingCopyName())
        let name = try copy.makeCopy(from: packFolder)
        XCTAssertEqual(name, "Graphite Guide")
        XCTAssertEqual(copy.existingCopyName(), "Graphite Guide", "The same copy opens the next time.")
        let vault = copy.documentsFolder.appendingPathComponent(name)
        XCTAssertEqual(try String(contentsOf: vault.appendingPathComponent("1 New to files/What a vault is.md"), encoding: .utf8), "A folder.")
        XCTAssertFalse(FileManager.default.fileExists(atPath: vault.appendingPathComponent(GuideVaultCopy.packMarkerFileName).path))
    }

    func testAFreshCopyGoesBesideTheOldOneAndLeavesItAsTheReaderLeftIt() throws {
        let first = try copy.makeCopy(from: packFolder)
        let changedNote = copy.documentsFolder.appendingPathComponent(first).appendingPathComponent("Start here.md")
        try Data("# My own notes".utf8).write(to: changedNote)

        let second = try copy.makeCopy(from: packFolder)

        XCTAssertEqual(second, "Graphite Guide 2")
        XCTAssertEqual(copy.existingCopyName(), "Graphite Guide 2", "The fresh copy is the one that opens from now on.")
        XCTAssertEqual(try String(contentsOf: changedNote, encoding: .utf8), "# My own notes")
        XCTAssertEqual(try String(contentsOf: copy.documentsFolder.appendingPathComponent(second).appendingPathComponent("Start here.md"), encoding: .utf8),
                       "# Welcome")
    }

    func testACopyTheReaderRemovedIsMadeAgain() throws {
        let name = try copy.makeCopy(from: packFolder)
        try FileManager.default.removeItem(at: copy.documentsFolder.appendingPathComponent(name))
        XCTAssertNil(copy.existingCopyName())
        XCTAssertEqual(try copy.makeCopy(from: packFolder), "Graphite Guide")
    }
}
