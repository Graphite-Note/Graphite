/**
 * File: SettingsPagesHostedTests.swift
 * ------------------------------------
 * Layer: Tests
 * Description: Hosted tests of the Settings pages on the iPad and the iPhone simulators: labels above their fields,
 *              colors that can be removed, a page that starts at its first screen, the font size slider, questions
 *              before anything is lost, the Pencil sections of the iPad only, pages without a vault and large text.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 02/11/2026
 */

#if os(iOS)
import XCTest
import SwiftUI
import GraphiteCore
@testable import GraphiteUI

/// What the Settings pages of the iPad and the iPhone show (the Settings section of the bug hunt, HUNT-239 to
/// HUNT-259). Run each on the iPad and on the iPhone simulator: a test that is only for one returns on the other.
@MainActor
final class SettingsPagesHostedTests: SettingsHostedTestCase {
    private func makeVault(files: [String: String] = ["Note.md": "x"]) throws -> URL {
        try TemporaryVault.make(prefix: "SettingsPagesHosted", files: files, for: self).root
    }

    private func settings(of workspace: WorkspaceModel, dynamicTypeSize: DynamicTypeSize = .large) throws -> UIHostingController<AnyView> {
        try host(SettingsView(workspace: workspace) {}.dynamicTypeSize(dynamicTypeSize))
    }

    /// Picks the page of the list as a finger does.
    private func open(_ page: String, in controller: UIViewController) async throws {
        await tap(try await element(in: controller, "the \(page) row") { $0.accessibilityLabel == page })
    }

    private func texts(of object: NSObject) -> [String] {
        [object.accessibilityLabel, object.accessibilityValue, object.accessibilityHint].compactMap { $0 }
    }

    // MARK: HUNT-239: a label above its field on a phone

    func testALabelSitsAboveItsFieldOnAPhoneAndBesideItOnAnIPad() async throws {
        let workspace = device.makeWorkspace()
        workspace.setCorePluginEnabled(.templates, true)
        try await workspace.openFolderAsVault(try makeVault())
        let controller = try settings(of: workspace)
        try await open("Templates", in: controller)

        var field: UITextField?
        try await waitUntil("the folder field", timeoutSeconds: 10) {
            field = self.textFields(in: controller.view).first { textField in textField.placeholder == "Templates" }
            return field != nil
        }
        let label = try await element(in: controller, "the label of the folder field") { object in
            object.accessibilityLabel == "Template Folder Location" && !(object is UITextField)
        }
        let fieldFrame = try XCTUnwrap(field).accessibilityFrame
        let labelFrame = label.accessibilityFrame
        if isPhone {
            XCTAssertLessThanOrEqual(labelFrame.maxY, fieldFrame.minY + 2, "On a phone the label is above the field, so it is not cut to “Template folder loc…”.")
            XCTAssertGreaterThan(labelFrame.width, fieldFrame.width * 0.6, "The label has the width of the row.")
        } else {
            XCTAssertGreaterThan(labelFrame.maxY, fieldFrame.minY, "Beside the field where the row is wide.")
        }
    }

    // MARK: HUNT-242, HUNT-250: the colors page

    func testAColorIsRemovedByItsOwnButtonAndTheListCanBeEdited() async throws {
        let workspace = device.makeWorkspace()
        workspace.setCorePluginEnabled(.colors, true)
        let controller = try settings(of: workspace)
        try await open("Colors", in: controller)

        let firstName = try XCTUnwrap(workspace.preferences.colorPalette.first).name
        let colorCount = workspace.preferences.colorPalette.count
        let removeButton = try await element(in: controller, "the button that removes \(firstName)") { $0.accessibilityLabel == "Remove \(firstName)" }
        XCTAssertTrue(removeButton.accessibilityActivate())
        try await waitUntil("the color is gone", timeoutSeconds: 10) { workspace.preferences.colorPalette.count == colorCount - 1 }
        XCTAssertFalse(workspace.preferences.colorPalette.contains { color in color.name == firstName })
        if !isPhone {
            _ = try await element(in: controller, "the Edit button, which lets rows be dragged") { $0.accessibilityLabel == "Edit" }
        }
    }

    func testRestoringTheDefaultPaletteAsksFirstAndIsOffWhenThereIsNothingToRestore() async throws {
        let workspace = device.makeWorkspace()
        workspace.setCorePluginEnabled(.colors, true)
        let controller = try settings(of: workspace)
        try await open("Colors", in: controller)

        let restoreWhenDefault = try await elementScrolling(in: controller, "Restore Default Palette") { $0.accessibilityLabel == "Restore Default Palette" }
        XCTAssertTrue(restoreWhenDefault.accessibilityTraits.contains(.notEnabled), "The palette is already the default.")

        workspace.preferences.colorPalette.append(PaletteColor(name: "mine", hex: "#123456"))
        let restore = try await elementScrolling(in: controller, "Restore Default Palette, enabled") {
            $0.accessibilityLabel == "Restore Default Palette" && !$0.accessibilityTraits.contains(.notEnabled)
        }
        XCTAssertTrue(restore.accessibilityActivate())
        _ = try await element(in: controller, "the question") { $0.accessibilityLabel == "Replace your palette with the default colors?" }
        XCTAssertTrue(workspace.preferences.colorPalette.contains { color in color.name == "mine" }, "Nothing is replaced before the person agrees.")
    }

    // MARK: HUNT-244, HUNT-251: a page starts at its first screen

    func testTheFontPageNamesItsFontButtonAndAnotherPageDoesNotKeepIt() async throws {
        let workspace = device.makeWorkspace()
        try await workspace.openFolderAsVault(try makeVault())
        let controller = try settings(of: workspace)
        try await open("Appearance", in: controller)

        let interfaceFont = try await elementScrolling(in: controller, "the Interface Font row") {
            ($0.accessibilityLabel ?? "").hasPrefix("Interface Font") && $0.accessibilityTraits.contains(.button)
        }
        await tap(interfaceFont)
        _ = try await element(in: controller, "the system font button") { $0.accessibilityLabel == "Choose an Installed Font…" }

        guard !isPhone else { return }
        // Beside the list, another page replaces the font list; it does not stay pushed on the new page.
        await tap(try await element(in: controller, "the Editor row") { $0.accessibilityLabel == "Editor" })
        _ = try await element(in: controller, "the Editor page") { ($0.accessibilityLabel ?? "").hasPrefix("Default View for New Notes") }
        XCTAssertNil(find(in: controller) { $0.accessibilityLabel == "Choose an Installed Font…" }, "The font list of the Appearance page is gone.")
    }

    // MARK: HUNT-246, HUNT-248: the font size slider

    func testAFontSizeStepMadeByAccessibilityIsSavedAndAPhoneIsNotToldAboutKeys() async throws {
        let workspace = device.makeWorkspace()
        try await workspace.openFolderAsVault(try makeVault())
        let controller = try settings(of: workspace)
        try await open("Appearance", in: controller)

        let slider = try await elementScrolling(in: controller, "the Font Size slider") {
            $0.accessibilityLabel == "Font Size" && $0.accessibilityTraits.contains(.adjustable)
        }
        let sizeBefore = workspace.noteBaseFontSize
        slider.accessibilityIncrement()
        try await waitUntil("the size is applied", timeoutSeconds: 10) { workspace.noteBaseFontSize > sizeBefore }
        XCTAssertEqual(workspace.vaultAppearance.baseFontSize, workspace.noteBaseFontSize, "The step is saved, not only shown.")

        if isPhone {
            let pinch = try await elementScrolling(in: controller, "the quick adjustment text") { object in
                self.texts(of: object).contains { text in text.contains("Pinch a note with two fingers") }
            }
            XCTAssertFalse(texts(of: pinch).contains { text in text.contains("⌘") }, "A phone has no keyboard shortcuts to name.")
        }
    }

    // MARK: HUNT-255: Pencil sections for the iPad

    func testThePencilSectionsAreForTheIPadOnly() async throws {
        let workspace = device.makeWorkspace()
        workspace.setCorePluginEnabled(.drawings, true)
        let controller = try settings(of: workspace)
        try await open("Pencil Drawings", in: controller)

        if isPhone {
            _ = try await element(in: controller, "the Paper section") { $0.accessibilityLabel == "Paper" }
            while scrollDown(in: controller) { try await Task.sleep(for: .milliseconds(100)) }
            for pencilOnly in ["Palm Rejection", "Hold to Make a Shape", "Pencil Tools", "Highlighter Ignores Tilt"] {
                XCTAssertNil(find(in: controller) { object in self.texts(of: object).contains(pencilOnly) }, "\(pencilOnly) has no effect on a phone.")
            }
        } else {
            _ = try await elementScrolling(in: controller, "Palm Rejection") { object in self.texts(of: object).contains("Palm Rejection") }
        }
    }

    // MARK: HUNT-252, HUNT-256: the list names the vault, the Editor page has the typing switches

    func testTheListNamesTheVaultItsPagesChange() async throws {
        let workspace = device.makeWorkspace()
        try await workspace.openFolderAsVault(try makeVault())
        let identifier = try XCTUnwrap(workspace.currentVaultIdentifier)
        let vaultName = try XCTUnwrap(workspace.vaultLibrary.vault(withIdentifier: identifier)).name
        let controller = try settings(of: workspace)
        _ = try await elementScrolling(in: controller, "the vault named under the list") { object in
            self.texts(of: object).contains("Vault settings on these pages are for “\(vaultName)”.")
        }
    }

    func testTheEditorPageHasTheTabSwitchesForEveryScreen() async throws {
        let workspace = device.makeWorkspace()
        try await workspace.openFolderAsVault(try makeVault(files: [".obsidian/app.json": "{\"useTab\": false}", "Note.md": "x"]))
        let controller = try settings(of: workspace)
        try await open("Editor", in: controller)
        for label in ["Indent Using Tabs", "Auto Convert HTML on Paste"] {
            _ = try await elementScrolling(in: controller, label) { object in self.texts(of: object).contains(label) }
        }
        _ = try await elementScrolling(in: controller, "Tab Indent Size") { object in self.texts(of: object).contains { text in text.hasPrefix("Tab Indent Size") } }
    }

    // MARK: HUNT-258: pages that need a vault say so

    func testPagesThatNeedAVaultSayWhenNoneIsOpen() async throws {
        let pages: [(plugin: CorePlugin?, row: String, text: String)] = [
            (.templates, "Templates", "Open a vault to change its template settings."),
            (.dailyNotes, "Daily Notes", "Open a vault to change its daily notes settings."),
            (nil, "Editor", "Open a vault to change its typing settings."),
            (nil, "Community Plugins", "Open a vault to change its community plugins."),
            (nil, "Keyboard Shortcuts", "Open a vault to change its keyboard shortcuts."),
        ]
        for page in pages {
            let workspace = device.makeWorkspace()
            if let plugin = page.plugin { workspace.setCorePluginEnabled(plugin, true) }
            let controller = try settings(of: workspace)
            try await open(page.row, in: controller)
            _ = try await elementScrolling(in: controller, page.text) { $0.accessibilityLabel == page.text }
        }
    }

    // MARK: HUNT-259: shortcut rows at large text

    func testShortcutButtonsAreBigEnoughAndStackUnderTheNameAtLargeText() async throws {
        guard !isPhone else { return }
        let workspace = device.makeWorkspace()
        for (dynamicTypeSize, isStacked) in [(DynamicTypeSize.large, false), (.accessibility3, true)] {
            let controller = try settings(of: workspace, dynamicTypeSize: dynamicTypeSize)
            try await open("Keyboard Shortcuts", in: controller)
            let record = try await element(in: controller, "a Record Shortcut button at \(dynamicTypeSize)") { $0.accessibilityLabel == "Record Shortcut" }
            let frame = record.accessibilityFrame
            XCTAssertGreaterThanOrEqual(frame.width, 44, "A finger needs 44 points.")
            XCTAssertGreaterThanOrEqual(frame.height, 44)
            let windowWidth = try XCTUnwrap(window).bounds.width
            if isStacked {
                XCTAssertLessThan(frame.minX, windowWidth * 0.5, "At large text the buttons are under the name, from the left.")
            } else {
                XCTAssertGreaterThan(frame.maxX, windowWidth * 0.8, "The buttons are at the right end of the row.")
            }
        }
    }

    // MARK: HUNT-243: the vault manager fits a phone

    func testTheVaultManagerFitsTheWidthOfAPhone() {
        let sheet = NavigationStack { VaultManagerView(workspace: device.makeWorkspace()) }.sheetMinimumSize(width: 480, height: 360)
        let size = UIHostingController(rootView: sheet).sizeThatFits(in: CGSize(width: 390, height: 800))
        XCTAssertLessThanOrEqual(size.width, 390, "A minimum width of 480 points would be laid out wider than the screen and cut off.")
    }

    // MARK: HUNT-257: a theme is deleted only after a question

    func testDeletingAnInstalledThemeAsksFirst() async throws {
        guard !isPhone else { return }
        let vault = try makeVault(files: [".obsidian/themes/Other/theme.css": "body {}", "Note.md": "x"])
        let workspace = device.makeWorkspace()
        // Obsidian's list is already known, so the page does not go to the network.
        workspace.processServices.themeDirectoryCache.entries = [ObsidianThemeDirectoryEntry(name: "Minimal", author: "kepano", repo: "kepano/obsidian-minimal")]
        try await workspace.openFolderAsVault(vault)
        let controller = try settings(of: workspace)
        try await open("Appearance", in: controller)

        let themeLink = try await elementScrolling(in: controller, "the Theme row") {
            ($0.accessibilityLabel ?? "").hasPrefix("Theme") && $0.accessibilityTraits.contains(.button)
        }
        await tap(themeLink)
        let themeRow = try await element(in: controller, "the Other theme") { $0.accessibilityLabel == "Other" }
        let deleteAction = try XCTUnwrap(themeRow.accessibilityCustomActions?.first { action in action.name.hasPrefix("Delete") }, "Swiping a theme offers Delete.")
        XCTAssertTrue(deleteAction.actionHandler?(deleteAction) ?? false)

        _ = try await element(in: controller, "the question") { $0.accessibilityLabel == "Delete “Other”?" }
        XCTAssertTrue(FileManager.default.fileExists(atPath: vault.appendingPathComponent(".obsidian/themes/Other/theme.css").path), "Nothing is deleted before the person agrees.")
    }
}

#endif
