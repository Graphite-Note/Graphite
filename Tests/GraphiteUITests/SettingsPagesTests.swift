import XCTest
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

/// What Settings opens on, what its wording says, and what changing an option does to the
/// vault and the device (the Settings section of the bug hunt, HUNT-237 to HUNT-259).
@MainActor
final class SettingsPagesTests: XCTestCase {
    private var device: IsolatedWorkspaceDevice!

    override func setUp() async throws {
        device = try IsolatedWorkspaceDevice.make(for: self)
    }

    private func makeVault(files: [String: String] = [:]) throws -> URL {
        try TemporaryVault.make(prefix: "SettingsPagesVault", files: files, for: self).root
    }

    // MARK: HUNT-237: what Settings opens on

    func testAPhoneOpensOnTheListWhateverWasUsedBefore() {
        for remembered in [nil, SettingsPage.general, .appearance, .plugin(.colors)] {
            XCTAssertNil(SettingsOpening.openingPage(remembered: remembered, isNarrowScreen: true, isAvailable: { _ in true }))
        }
    }

    func testBesideTheListTheFirstOpeningIsGeneralAndLaterOnesAreTheLastPageUsed() {
        XCTAssertEqual(SettingsOpening.openingPage(remembered: nil, isNarrowScreen: false, isAvailable: { _ in true }), .general)
        XCTAssertEqual(SettingsOpening.openingPage(remembered: .appearance, isNarrowScreen: false, isAvailable: { _ in true }), .appearance)
        XCTAssertEqual(SettingsOpening.openingPage(remembered: .plugin(.templates), isNarrowScreen: false, isAvailable: { _ in true }), .plugin(.templates))
    }

    func testAPageThatIsGoneIsNotOpenedAgain() {
        // A core plugin turned off, or a community plugin removed, since the page was used.
        XCTAssertEqual(SettingsOpening.openingPage(remembered: .plugin(.dailyNotes), isNarrowScreen: false, isAvailable: { page in page != .plugin(.dailyNotes) }), .general)
        XCTAssertEqual(SettingsOpening.openingPage(remembered: .communityPlugin("gone"), isNarrowScreen: false, isAvailable: { _ in false }), .general)
    }

    func testTheLastPageIsKeptForTheWholeRunAndOpeningTheListChangesNothing() {
        let services = device.makeServices()
        let memory = services.settingsPageMemory
        XCTAssertNil(memory.lastPage)
        memory.remember(.editor)
        memory.remember(nil)
        XCTAssertEqual(memory.lastPage, .editor, "Backing out to the list on a phone does not forget the page.")
        memory.remember(.filesAndLinks)
        XCTAssertEqual(WorkspaceModel(processServices: services, clock: LiveApplicationClock()).processServices.settingsPageMemory.lastPage, .filesAndLinks,
                       "Every window and every opening of Settings shares one memory.")
    }

    // MARK: HUNT-240, HUNT-248: wording that fits the screen

    func testTheAppearanceSectionNamesTheSwitchOnlyWhereItCanBeSeen() {
        let listOnAPhone = LibrarySettingsSection.explanation(presentation: .list, isCompactWidth: true)
        XCTAssertFalse(listOnAPhone.contains("switch"), "A phone listing files as a tree has no switch beside them.")
        XCTAssertTrue(LibrarySettingsSection.explanation(presentation: .library, isCompactWidth: true).contains("top of the library"))
        XCTAssertTrue(LibrarySettingsSection.explanation(presentation: .list, isCompactWidth: false).contains("switch beside your files"))
        XCTAssertTrue(LibrarySettingsSection.explanation(presentation: .library, isCompactWidth: false).contains("switch beside your files"))
    }

    func testCorePluginSummariesNameTheLinksSheetWhereThereIsNoRightSidebar() {
        for plugin in [CorePlugin.footnotes, .graph, .map] {
            XCTAssertTrue(plugin.summary(hasRightSidebar: true).contains("right sidebar"), plugin.title)
            XCTAssertFalse(plugin.summary(hasRightSidebar: false).contains("right sidebar"), plugin.title)
            XCTAssertTrue(plugin.summary(hasRightSidebar: false).contains("Links and Outline"), plugin.title)
        }
        XCTAssertEqual(CorePlugin.backlinks.summary(hasRightSidebar: false), CorePlugin.backlinks.summary)
    }

    // MARK: HUNT-245: History length

    func testShorteningTheHistoryLengthRemovesOlderCopiesAtOnce() async throws {
        let workspace = device.makeWorkspace()
        let copies = FileRecoveryStore(directory: try makeVault().appendingPathComponent("Copies"))
        workspace.fileRecovery = copies
        let path = try VaultPath("Note.md")
        try copies.takeSnapshot(of: "ten days old", for: path, at: Date.now.addingTimeInterval(-10 * 86_400), minimumInterval: 0)
        try copies.takeSnapshot(of: "an hour old", for: path, at: Date.now.addingTimeInterval(-3_600), minimumInterval: 0)
        workspace.preferences.snapshotHistoryDays = 30

        await workspace.changeSnapshotHistoryDays(20)?.value
        XCTAssertEqual(try copies.snapshots(for: path).count, 2, "Nothing is older than 20 days.")

        await workspace.changeSnapshotHistoryDays(5)?.value
        XCTAssertEqual(workspace.preferences.snapshotHistoryDays, 5)
        XCTAssertEqual(try copies.snapshots(for: path).map { snapshot in try copies.text(of: snapshot) }, ["an hour old"])
    }

    func testChangingTheHistoryLengthWithNoVaultOpenOnlyKeepsIt() {
        let workspace = device.makeWorkspace()
        XCTAssertNil(workspace.changeSnapshotHistoryDays(12))
        XCTAssertEqual(workspace.preferences.snapshotHistoryDays, 12)
    }

    // MARK: HUNT-253: options Obsidian keeps in app.json

    func testAVaultThatSetsEditorOptionsIsHonouredAndOthersFollowTheDevice() async throws {
        let workspace = device.makeWorkspace()
        workspace.preferences.usesReadableLineLength = true
        workspace.preferences.showsInlineTitle = true
        workspace.preferences.usesSpellChecking = true
        workspace.preferences.defaultNoteView = .editing
        workspace.preferences.defaultEditingMode = .livePreview

        try await workspace.openFolderAsVault(try makeVault(files: [".obsidian/app.json": "{\"readableLineLength\": false, \"showInlineTitle\": false, \"spellcheck\": false, \"defaultViewMode\": \"preview\", \"livePreview\": false}", "Note.md": "x"]))
        XCTAssertFalse(workspace.usesReadableLineLength)
        XCTAssertFalse(workspace.showsInlineTitle)
        XCTAssertFalse(workspace.usesSpellChecking)
        XCTAssertEqual(workspace.defaultNoteView, .reading)
        XCTAssertEqual(workspace.defaultEditingMode, .source)
        XCTAssertEqual(workspace.initialNoteViewMode, .reading)

        let otherWorkspace = device.makeWorkspace()
        try await otherWorkspace.openFolderAsVault(try makeVault(files: [".obsidian/app.json": "{\"vimMode\": true}", "Note.md": "x"]))
        XCTAssertTrue(otherWorkspace.usesReadableLineLength, "The vault does not say, so this device's choice applies.")
        XCTAssertTrue(otherWorkspace.showsInlineTitle)
        XCTAssertTrue(otherWorkspace.usesSpellChecking)
        XCTAssertEqual(otherWorkspace.defaultNoteView, .editing)
        XCTAssertEqual(otherWorkspace.initialNoteViewMode, .livePreview)
    }

    func testChoosingAnEditorOptionWritesOnlyThatKeyIntoAppJSON() async throws {
        let workspace = device.makeWorkspace()
        let vault = try makeVault(files: [".obsidian/app.json": "{\n  \"vimMode\": true,\n  \"newLinkFormat\": \"relative\"\n}", "Note.md": "x"])
        try await workspace.openFolderAsVault(vault)

        var settings = workspace.vaultSettings
        settings.usesReadableLineLength = false
        settings.defaultViewMode = .preview
        await workspace.updateVaultSettings(settings)

        let written = try String(contentsOf: vault.appendingPathComponent(".obsidian/app.json"), encoding: .utf8)
        XCTAssertEqual(written, "{\n  \"vimMode\": true,\n  \"newLinkFormat\": \"relative\",\n  \"readableLineLength\": false,\n  \"defaultViewMode\": \"preview\"\n}")
        XCTAssertFalse(workspace.usesReadableLineLength)
        XCTAssertEqual(workspace.defaultNoteView, .reading)
        XCTAssertTrue(workspace.preferences.usesReadableLineLength, "The device's own choice is not touched by the vault's.")
    }
}

// MARK: HUNT-257: removing an installed theme

extension SettingsPagesTests {
    func testDeletingTheThemeInUseRemovesItsFolderAndSwitchesItOff() async throws {
        let workspace = device.makeWorkspace()
        let vault = try makeVault(files: [".obsidian/appearance.json": "{\"cssTheme\": \"Minimal\"}", ".obsidian/themes/Minimal/theme.css": "body {}",
                                          ".obsidian/themes/Other/theme.css": "body {}", "Note.md": "x"])
        try await workspace.openFolderAsVault(vault)
        // Permanently, so the test does not put files in the Trash of the machine that runs it.
        var settings = workspace.vaultSettings
        settings.deletionMethod = .permanent
        await workspace.updateVaultSettings(settings)
        XCTAssertEqual(workspace.vaultAppearance.cssTheme, "Minimal")

        try await workspace.deleteInstalledTheme(named: "Minimal")

        XCTAssertFalse(FileManager.default.fileExists(atPath: vault.appendingPathComponent(".obsidian/themes/Minimal").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: vault.appendingPathComponent(".obsidian/themes/Other/theme.css").path), "Other themes stay.")
        XCTAssertEqual(workspace.vaultAppearance.cssTheme, "", "The vault no longer names a theme it lacks.")
        let appearanceFile = try String(contentsOf: vault.appendingPathComponent(".obsidian/appearance.json"), encoding: .utf8)
        XCTAssertFalse(appearanceFile.contains("Minimal"))
    }

    func testDeletingAnotherThemeLeavesTheChosenOneAlone() async throws {
        let workspace = device.makeWorkspace()
        let vault = try makeVault(files: [".obsidian/appearance.json": "{\"cssTheme\": \"Minimal\"}", ".obsidian/themes/Minimal/theme.css": "body {}",
                                          ".obsidian/themes/Other/theme.css": "body {}", "Note.md": "x"])
        try await workspace.openFolderAsVault(vault)
        var settings = workspace.vaultSettings
        settings.deletionMethod = .permanent
        await workspace.updateVaultSettings(settings)

        try await workspace.deleteInstalledTheme(named: "Other")

        XCTAssertEqual(workspace.vaultAppearance.cssTheme, "Minimal")
        let installedThemes = await workspace.store?.installedThemeNames()
        XCTAssertEqual(installedThemes, ["Minimal"])
    }
}
