/**
 * File: KeyboardShortcutsPageContentTests.swift
 * ---------------------------------------------
 * Layer: Tests
 * Description: What Settings › Keyboard Shortcuts lists: groups, search, clashes and the system's notes.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 11/11/2026
 */
import XCTest
import GraphiteCore
@testable import GraphiteUI

/// What Settings › Keyboard Shortcuts lists: groups, search, clashes and the system's notes.
@MainActor
final class KeyboardShortcutsPageContentTests: XCTestCase {
    private let pluginCommand = CommunityPluginCommand(id: "quick-add:run", name: "QuickAdd: Run", needsEditor: false, pluginIdentifier: "quick-add",
                                                       defaultCombinations: [KeyCombination([.command, .shift], .character("Q"))])

    private func content(file: HotkeyFile = HotkeyFile(), platform: ShortcutPlatform = .macOS, enabled: Set<CorePlugin> = Set(CorePlugin.allCases),
                         systemSettingsShortcuts: [String: KeyCombination?] = [:]) -> KeyboardShortcutsPageContent {
        let commands = GraphiteCommand.available(on: platform).map(\.defaults)
            + [ShortcutCommandDefaults(identifier: pluginCommand.id, defaultCombinations: pluginCommand.defaultCombinations)]
        return KeyboardShortcutsPageContent(table: KeyboardShortcutTable(commands: commands, file: file), platform: platform, pluginCommands: [pluginCommand],
                                            pluginName: { identifier in identifier == "quick-add" ? "QuickAdd" : nil },
                                            isCorePluginEnabled: { plugin in enabled.contains(plugin) }, systemSettingsShortcuts: systemSettingsShortcuts)
    }

    private func row(_ identifier: String, in content: KeyboardShortcutsPageContent) throws -> KeyboardShortcutRow {
        try XCTUnwrap(content.sections(matching: "").flatMap(\.rows).first { row in row.id == identifier }, identifier)
    }

    func testListsGraphitesGroupsThenEachPluginByName() {
        let titles = content().sections(matching: "").map(\.title)
        XCTAssertEqual(titles, ["File", "View", "Go", "Editor", "Canvas", "PDF", "QuickAdd"])
        XCTAssertEqual(content(platform: .iPadOS).sections(matching: "").map(\.title), ["File", "View", "Go", "Editor", "Canvas", "QuickAdd"],
                       "The iPad has no PDF markup commands.")
    }

    func testFindsCommandsByTitleBySymbolsAndBySpokenShortcut() {
        let byTitle = content().sections(matching: "bold").flatMap(\.rows).map(\.id)
        XCTAssertEqual(byTitle, [GraphiteCommand.toggleBold.identifier])
        let bySymbols = content().sections(matching: "⌘B").flatMap(\.rows).map(\.id)
        XCTAssertEqual(bySymbols, [GraphiteCommand.toggleBold.identifier])
        let byWords = content().sections(matching: "shift command q").flatMap(\.rows).map(\.id)
        XCTAssertEqual(byWords, [pluginCommand.id])
    }

    func testExportToPDFIsListedUnderFileWithShiftCommandEAndCanBeChanged() throws {
        for platform in [ShortcutPlatform.macOS, .iPadOS] {
            let page = content(platform: platform)
            let fileRows = try XCTUnwrap(page.sections(matching: "").first { section in section.title == "File" }).rows.map(\.id)
            XCTAssertTrue(fileRows.contains(GraphiteCommand.exportToPDF.identifier), "\(platform)")
            XCTAssertEqual(page.sections(matching: "⇧⌘E").flatMap(\.rows).map(\.id), [GraphiteCommand.exportToPDF.identifier], "\(platform)")
            let row = try row(GraphiteCommand.exportToPDF.identifier, in: page)
            XCTAssertEqual(row.sharedWithTitles, [], "\(platform)")
            XCTAssertTrue(row.systemShortcuts.isEmpty, "\(platform)")
        }
        var file = HotkeyFile()
        file.assign([KeyCombination([.command, .option], .character("E"))], to: GraphiteCommand.exportToPDF.identifier)
        let changed = try row(GraphiteCommand.exportToPDF.identifier, in: content(file: file))
        XCTAssertTrue(changed.isChanged)
        XCTAssertEqual(changed.combinations.map(\.symbols), ["⌥⌘E"])
    }

    func testMarksBothCommandsOfAClashAndTheSystemsShortcuts() throws {
        var file = HotkeyFile()
        file.assign([KeyCombination(.command, .character("B"))], to: GraphiteCommand.newNotebook.identifier)
        file.assign([KeyCombination(.command, .named(.tab))], to: GraphiteCommand.newTab.identifier)
        file.assign([KeyCombination(.command, .character("Q"))], to: GraphiteCommand.closeTab.identifier)
        let page = content(file: file)

        XCTAssertEqual(try row(GraphiteCommand.newNotebook.identifier, in: page).sharedWithTitles, ["Toggle bold"])
        XCTAssertEqual(try row(GraphiteCommand.toggleBold.identifier, in: page).sharedWithTitles, ["Create new notebook"])
        XCTAssertEqual(try row(GraphiteCommand.newTab.identifier, in: page).systemShortcuts.map(\.kind), [.reserved])
        XCTAssertEqual(try row(GraphiteCommand.closeTab.identifier, in: page).systemShortcuts.map(\.purpose), [.quit])
        XCTAssertTrue(try row(GraphiteCommand.closeTab.identifier, in: page).isChanged)
    }

    func testShowsTheMacsSystemSettingsShortcutOnTheRowOfItsMenuItem() throws {
        let override = KeyCombination([.command, .option], .character("N"))
        let page = content(systemSettingsShortcuts: ["New Note": override, "Close Tab": nil])

        XCTAssertEqual(try row(GraphiteCommand.newNote.identifier, in: page).systemSettingsOverride, .some(override))
        XCTAssertEqual(try row(GraphiteCommand.closeTab.identifier, in: page).systemSettingsOverride, .some(nil))
        XCTAssertEqual(try row(GraphiteCommand.newTab.identifier, in: page).systemSettingsOverride, nil as KeyCombination??)
    }

    func testCommandsOfACorePluginThatIsOffAreNotListedAndTheIPadKeepsItsOwnCommands() {
        let withoutCanvas = content(enabled: Set(CorePlugin.allCases).subtracting([.canvas])).sections(matching: "")
        XCTAssertFalse(withoutCanvas.map(\.title).contains("Canvas"))
        XCTAssertFalse(withoutCanvas.flatMap(\.rows).contains { row in row.id == GraphiteCommand.newCanvas.identifier })

        let macRows = content(platform: .macOS).sections(matching: "").flatMap(\.rows).map(\.id)
        let iPadRows = content(platform: .iPadOS).sections(matching: "").flatMap(\.rows).map(\.id)
        XCTAssertFalse(macRows.contains(GraphiteCommand.followLink.identifier), "The Mac follows links with a click.")
        XCTAssertTrue(iPadRows.contains(GraphiteCommand.followLink.identifier))
        XCTAssertTrue(iPadRows.contains(GraphiteCommand.openSettings.identifier))
    }
}
