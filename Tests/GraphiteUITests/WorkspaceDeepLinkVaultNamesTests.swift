/**
 * File: WorkspaceDeepLinkVaultNamesTests.swift
 * --------------------------------------------
 * Layer: Tests
 * Description: graphite:// links to vaults that share a folder name, obsidian://new with a full path, and links whose vault switch was skipped.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 02/11/2026
 */

import XCTest
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

@MainActor
final class WorkspaceDeepLinkVaultNamesTests: XCTestCase {
    private var device: IsolatedWorkspaceDevice!
    private var parentFolder: URL!

    override func setUp() async throws {
        device = try IsolatedWorkspaceDevice.make(for: self)
        parentFolder = try TemporaryVault.make(prefix: "DeepLinkNames", for: self).root.resolvingSymlinksInPath()
    }

    /// A vault folder named `name` inside a folder of its own, so two can share the name.
    private func makeVault(named name: String, in group: String, files: [String: String]) throws -> URL {
        let vault = parentFolder.appendingPathComponent(group).appendingPathComponent(name)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        for (path, contents) in files { try Data(contents.utf8).write(to: vault.appendingPathComponent(path)) }
        return vault
    }

    /// HUNT-191: the link named the vault by its folder, and the first vault of that name opened.
    func testALinkCopiedInOneOfTwoSameNamedVaultsOpensThatVault() async throws {
        let firstVault = try makeVault(named: "Notes", in: "One", files: ["Note.md": "First."])
        let secondVault = try makeVault(named: "Notes", in: "Two", files: ["Note.md": "Second."])
        let workspace = device.makeWorkspace()
        try await workspace.openFolderAsVault(firstVault)
        let firstIdentifier = try XCTUnwrap(workspace.currentVaultIdentifier)
        try await workspace.openFolderAsVault(secondVault)
        let secondIdentifier = try XCTUnwrap(workspace.currentVaultIdentifier)
        let linkInSecond = workspace.openingLink(to: try VaultPath("Note.md"))
        try await workspace.openFolderAsVault(firstVault)
        let linkInFirst = workspace.openingLink(to: try VaultPath("Note.md"))

        XCTAssertTrue(linkInSecond.contains("vault=" + secondIdentifier.uuidString), "The vault is named by its identifier: \(linkInSecond)")
        XCTAssertTrue(linkInFirst.contains("vault=" + firstIdentifier.uuidString))

        await workspace.handle(try XCTUnwrap(URL(string: linkInSecond)))
        XCTAssertEqual(workspace.currentVaultIdentifier, secondIdentifier)
        XCTAssertEqual(workspace.selection?.rawValue, "Note.md")
        await workspace.handle(try XCTUnwrap(URL(string: linkInFirst)))
        XCTAssertEqual(workspace.currentVaultIdentifier, firstIdentifier)
    }

    func testTheOpenVaultAnswersToItsNameBeforeAnotherVaultOfTheSameName() async throws {
        let firstVault = try makeVault(named: "Notes", in: "One", files: ["Note.md": "First."])
        let secondVault = try makeVault(named: "Notes", in: "Two", files: ["Note.md": "Second."])
        let workspace = device.makeWorkspace()
        for vault in [firstVault, secondVault, firstVault, secondVault] {
            try await workspace.openFolderAsVault(vault)
            XCTAssertTrue(workspace.isCurrentVault(named: "Notes"), "A link by name does not switch away from the open vault.")
        }
    }

    func testALinkNamesTheVaultByItsFolderWhenNoOtherVaultHasThatName() async throws {
        let vault = try makeVault(named: "Physics", in: "One", files: ["Note.md": "Note."])
        let workspace = device.makeWorkspace()
        try await workspace.openFolderAsVault(vault)

        XCTAssertEqual(workspace.openingLink(to: try VaultPath("Note.md")), "graphite://open?vault=Physics&file=Note",
                       "As Obsidian writes them, so the link works there too.")
    }

    /// HUNT-199: `path` was ignored for `new`, which made "Untitled" in the new-note folder.
    func testANewNoteLinkWithAFullPathMakesTheNoteAtThatPath() async throws {
        let vault = try makeVault(named: "Physics", in: "One", files: ["Open.md": "Open."])
        let workspace = device.makeWorkspace()
        try await workspace.openFolderAsVault(vault)
        let notePath = vault.appendingPathComponent("Notes/Idea").path
        var components = URLComponents()
        components.scheme = "graphite"
        components.host = "new"
        components.queryItems = [URLQueryItem(name: "vault", value: "Physics"), URLQueryItem(name: "path", value: notePath), URLQueryItem(name: "content", value: "hello")]

        await workspace.handle(try XCTUnwrap(components.url))

        XCTAssertNil(workspace.errorMessage)
        XCTAssertEqual(try String(contentsOf: vault.appendingPathComponent("Notes/Idea.md"), encoding: .utf8), "hello")
        XCTAssertFalse(FileManager.default.fileExists(atPath: vault.appendingPathComponent("Untitled.md").path))
        XCTAssertEqual(workspace.selection?.rawValue, "Notes/Idea.md")
    }

    func testANewNoteLinkWithAPathOutsideEveryVaultSaysSoAndMakesNothing() async throws {
        let vault = try makeVault(named: "Physics", in: "One", files: ["Open.md": "Open."])
        let workspace = device.makeWorkspace()
        try await workspace.openFolderAsVault(vault)
        var components = URLComponents()
        components.scheme = "graphite"
        components.host = "new"
        components.queryItems = [URLQueryItem(name: "path", value: "/nowhere/Else/Idea"), URLQueryItem(name: "content", value: "hello")]

        await workspace.handle(try XCTUnwrap(components.url))

        XCTAssertNotNil(workspace.errorMessage)
        XCTAssertFalse(FileManager.default.fileExists(atPath: vault.appendingPathComponent("Untitled.md").path))
    }

    // MARK: A link whose vault switch was skipped

    /// Three vaults known to Graphite, `Third` open, each with its own `Note.md`.
    private func makeThreeVaults() throws -> (workspace: WorkspaceModel, first: URL, second: URL, third: URL) {
        (device.makeWorkspace(),
         try makeVault(named: "First", in: "One", files: ["Note.md": "First's own."]),
         try makeVault(named: "Second", in: "Two", files: ["Note.md": "Second's own."]),
         try makeVault(named: "Third", in: "Three", files: ["Note.md": "Third's own."]))
    }

    /// A link that waits for a switch running while a newer pick arrives: its own switch is skipped.
    private func handleLinkWhoseSwitchIsSkipped(_ link: URL, workspace: WorkspaceModel, first: URL, second: URL, third: URL) async throws {
        for vault in [first, second, third] { try await workspace.openFolderAsVault(vault) }
        let firstKnown = try XCTUnwrap(workspace.vaultLibrary.vaults.first { vault in vault.name == "First" })
        // Started in this order, each runs up to its first wait before the next starts.
        let runningSwitch = Task { try await workspace.openVault(firstKnown) }
        let linkFollowing = Task { await workspace.handle(link) }
        let newerPick = Task { try await workspace.openVault(firstKnown) }
        await linkFollowing.value
        try await runningSwitch.value
        try await newerPick.value
        XCTAssertEqual(workspace.currentVaultIdentifier, firstKnown.id)
    }

    private func assertEveryNoteIsAsItWas(first: URL, second: URL, third: URL, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(try String(contentsOf: first.appendingPathComponent("Note.md"), encoding: .utf8), "First's own.", file: file, line: line)
        XCTAssertEqual(try String(contentsOf: second.appendingPathComponent("Note.md"), encoding: .utf8), "Second's own.", file: file, line: line)
        XCTAssertEqual(try String(contentsOf: third.appendingPathComponent("Note.md"), encoding: .utf8), "Third's own.", file: file, line: line)
    }

    /// The link named `Second`; it must not overwrite the same-named note of whichever vault is open.
    func testALinkWhoseSwitchWasSkippedDoesNotOverwriteANoteOfTheVaultOpen() async throws {
        let (workspace, first, second, third) = try makeThreeVaults()
        var components = URLComponents()
        components.scheme = "graphite"
        components.host = "new"
        components.queryItems = [URLQueryItem(name: "vault", value: "Second"), URLQueryItem(name: "file", value: "Note"),
                                 URLQueryItem(name: "content", value: "From the link"), URLQueryItem(name: "overwrite", value: "true")]
        try await handleLinkWhoseSwitchIsSkipped(try XCTUnwrap(components.url), workspace: workspace, first: first, second: second, third: third)
        try assertEveryNoteIsAsItWas(first: first, second: second, third: third)
        XCTAssertNotNil(workspace.errorMessage, "The person is told the link was not followed: its content would otherwise be lost silently.")
    }

    func testALinkByFullPathWhoseSwitchWasSkippedDoesNotActInTheVaultOpen() async throws {
        let (workspace, first, second, third) = try makeThreeVaults()
        var components = URLComponents()
        components.scheme = "graphite"
        components.host = "new"
        components.queryItems = [URLQueryItem(name: "path", value: second.appendingPathComponent("Note").path),
                                 URLQueryItem(name: "content", value: "From the link"), URLQueryItem(name: "overwrite", value: "true")]
        try await handleLinkWhoseSwitchIsSkipped(try XCTUnwrap(components.url), workspace: workspace, first: first, second: second, third: third)
        try assertEveryNoteIsAsItWas(first: first, second: second, third: third)
        XCTAssertNotNil(workspace.errorMessage)
    }
}
