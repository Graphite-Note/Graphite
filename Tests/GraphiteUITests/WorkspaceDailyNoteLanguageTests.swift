/**
 * File: WorkspaceDailyNoteLanguageTests.swift
 * -------------------------------------------
 * Layer: Tests
 * Description: Opening daily notes in a vault whose Obsidian uses another language makes no second note (HUNT-154).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 02/11/2026
 */

import XCTest
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

@MainActor
final class WorkspaceDailyNoteLanguageTests: XCTestCase {
    private let testBed = WorkspaceModelTestBed()
    private let settingsFile = [".obsidian/daily-notes.json": #"{"format": "dddd, DD. MMMM YYYY"}"#]

    override func tearDown() async throws {
        testBed.tearDown()
    }

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) throws -> Date {
        try XCTUnwrap(Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: dayOfMonth, hour: 12)))
    }

    /// A file the vault held when it opened reaches the index a moment later.
    private func waitUntilIndexed(_ rawPath: String, in workspace: WorkspaceModel) async throws {
        let path = try VaultPath(rawPath)
        let index = try XCTUnwrap(workspace.index)
        try await waitUntil("\(rawPath) reaches the index") { try await index.paths(inside: .root).contains(path) }
    }

    private func notes(in vault: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: vault.path).filter { name in name.hasSuffix(".md") }.sorted()
    }

    func testOpeningTheDayFindsTheGermanNoteAndMakesNoSecond() async throws {
        let (workspace, vault) = try await testBed.openedWorkspace(files: settingsFile.merging(["Sonntag, 01. November 2026.md": "Geschrieben von Obsidian\n"]) { first, _ in first })
        workspace.preferences.dateNameLanguage = .named("de")

        await workspace.openDailyNote(for: try day(2026, 11, 1))

        XCTAssertEqual(try notes(in: vault), ["Sonntag, 01. November 2026.md"], "With the setting, the existing file opens.")
        XCTAssertEqual(workspace.selection?.rawValue, "Sonntag, 01. November 2026.md")
    }

    /// English stays the default, so a vault's existing names are found and no setting is needed for them.
    func testEnglishIsTheDefaultAndFindsAVaultsEnglishNote() async throws {
        let (workspace, vault) = try await testBed.openedWorkspace(files: settingsFile.merging(["Sunday, 01. November 2026.md": "x\n"]) { first, _ in first })
        XCTAssertEqual(workspace.preferences.dateNameLanguage, .english)
        await workspace.openDailyNote(for: try day(2026, 11, 1))
        XCTAssertEqual(try notes(in: vault), ["Sunday, 01. November 2026.md"])
    }

    func testANoteNamedBeforeTheLanguageChangedOpensInsteadOfASecond() async throws {
        let (workspace, vault) = try await testBed.openedWorkspace(files: settingsFile.merging(["Sunday, 01. November 2026.md": "x\n"]) { first, _ in first })
        workspace.preferences.dateNameLanguage = .named("de")
        await workspace.openDailyNote(for: try day(2026, 11, 1))
        XCTAssertEqual(try notes(in: vault), ["Sunday, 01. November 2026.md"])
        XCTAssertEqual(workspace.selection?.rawValue, "Sunday, 01. November 2026.md")

        await workspace.openDailyNote(for: try day(2026, 11, 2))
        XCTAssertEqual(try notes(in: vault), ["Montag, 02. November 2026.md", "Sunday, 01. November 2026.md"], "A new note has the language chosen.")
    }

    /// Obsidian writes `Sep.` where Foundation has `Sept.`: the note is found by its date, not made again.
    func testAnAbbreviationOfObsidiansFindsItsNote() async throws {
        let (workspace, vault) = try await testBed.openedWorkspace(files: [
            ".obsidian/daily-notes.json": #"{"format": "DD. MMM YYYY"}"#, "01. Sep. 2026.md": "x\n",
        ])
        workspace.preferences.dateNameLanguage = .named("de")
        try await waitUntilIndexed("01. Sep. 2026.md", in: workspace)
        await workspace.openDailyNote(for: try day(2026, 9, 1))
        XCTAssertEqual(try notes(in: vault), ["01. Sep. 2026.md"])
    }

    func testPreviousAndNextMoveAcrossNamesInBothLanguages() async throws {
        let (workspace, _) = try await testBed.openedWorkspace(files: settingsFile.merging([
            "Freitag, 30. Oktober 2026.md": "x\n", "Sunday, 01. November 2026.md": "x\n", "Dienstag, 03. November 2026.md": "x\n",
        ]) { first, _ in first })
        workspace.preferences.dateNameLanguage = .named("de")
        try await waitUntilIndexed("Dienstag, 03. November 2026.md", in: workspace)
        await workspace.open(try VaultPath("Sunday, 01. November 2026.md"))

        await workspace.openAdjacentDailyNote(forward: true)
        XCTAssertEqual(workspace.selection?.rawValue, "Dienstag, 03. November 2026.md")
        await workspace.openAdjacentDailyNote(forward: false)
        await workspace.openAdjacentDailyNote(forward: false)
        XCTAssertEqual(workspace.selection?.rawValue, "Freitag, 30. Oktober 2026.md")
    }

    func testTheLanguageIsKeptOnTheDeviceWithTheOnesBeforeIt() throws {
        let suiteName = "WorkspaceDailyNoteLanguageTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = GraphitePreferences(defaults: defaults)
        XCTAssertEqual(preferences.dateNameLanguage, .english)
        XCTAssertEqual(preferences.dateNameReadingLanguages, [.english])
        preferences.dateNameLanguage = .named("de")
        preferences.dateNameLanguage = .named("fr")

        let reopened = GraphitePreferences(defaults: defaults)
        XCTAssertEqual(reopened.dateNameLanguage.id, "fr")
        XCTAssertEqual(reopened.dateNameReadingLanguages.map(\.id), ["fr", "de", "en"], "Notes in German are still found after moving on from it.")
    }
}
