/**
 * File: SettingsPagesHostedTests.swift
 * ------------------------------------
 * Layer: Tests
 * Description: Hosted tests of the Settings pages on the iPad and the iPhone simulators: labels above their fields,
 *              colors that can be removed, a page that starts at its first screen, the font size slider, questions
 *              before anything is lost, the Pencil sections of the iPad only, pages without a vault and large text, and
 *              the phone's layout in a compact width.
 *
 * Authors: Bahey Shalash
 * Version: 0.5
 * Date: 04/11/2026
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

    /// Settings in a window as wide as an iPhone 17 Pro, at a compact width: the layout a phone gets.
    private func phoneWidthSettings(of workspace: WorkspaceModel) throws -> UIHostingController<AnyView> {
        try host(SettingsView(workspace: workspace) {}, size: CGSize(width: 402, height: 874), horizontalSizeClass: .compact)
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
        let title = "Template Folder Location"
        let folderField = try XCTUnwrap(field)
        if isPhone {
            let label = try await element(in: controller, "the label of the folder field") { object in
                object.accessibilityLabel == title && !(object is UITextField)
            }
            let fieldFrame = folderField.accessibilityFrame
            let labelFrame = label.accessibilityFrame
            XCTAssertLessThanOrEqual(labelFrame.maxY, fieldFrame.minY + 2, "On a phone the label is above the field, so it is not cut to “Template folder loc…”.")
            XCTAssertGreaterThan(labelFrame.width, fieldFrame.width * 0.6, "The label has the width of the row.")
        } else {
            // LabeledContent makes its label the field's name for VoiceOver, so on a wide row the
            // label has no element of its own to measure. The field leaves the room for it instead:
            // under the label it would start at the row's edge, and beside a cut label, sooner.
            let page = try XCTUnwrap(sequence(first: folderField as UIView) { view in view.superview }.first { view in view is UIScrollView })
            let labelWidth = (title as NSString).size(withAttributes: [.font: UIFont.preferredFont(forTextStyle: .body)]).width
            let fieldMinX = folderField.convert(folderField.bounds, to: nil).minX
            XCTAssertGreaterThanOrEqual(fieldMinX - page.convert(page.bounds, to: nil).minX, labelWidth, "Beside the whole label where the row is wide.")
        }
    }

    /// HUNT-239 at a phone's width on any simulator: the field's label is above it, as wide as the row.
    func testALabelSitsAboveItsFieldInACompactWidth() async throws {
        let workspace = device.makeWorkspace()
        workspace.setCorePluginEnabled(.templates, true)
        try await workspace.openFolderAsVault(try makeVault())
        let controller = try phoneWidthSettings(of: workspace)
        try await open("Templates", in: controller)

        var field: UITextField?
        try await waitUntil("the folder field", timeoutSeconds: 10) {
            field = self.textFields(in: controller.view).first { textField in textField.placeholder == "Templates" }
            return field != nil
        }
        let folderField = try XCTUnwrap(field)
        let label = try await element(in: controller, "the label of the folder field, an element of its own above it") { object in
            object.accessibilityLabel == "Template Folder Location" && !(object is UITextField)
        }
        let fieldFrame = folderField.accessibilityFrame
        let labelFrame = label.accessibilityFrame
        XCTAssertLessThanOrEqual(labelFrame.maxY, fieldFrame.minY + 2, "At a compact width the label is above the field, so it is not cut to “Template folder loc…”.")
        XCTAssertGreaterThan(labelFrame.width, (("Template Folder Location" as NSString).size(withAttributes: [.font: UIFont.preferredFont(forTextStyle: .body)]).width) - 2,
                             "The whole label shows.")
        XCTAssertGreaterThan(fieldFrame.width, 250, "The field has the row's width under it.")
    }

    /// HUNT-248 at a phone's width: Core Plugins names the Links and Outline sheet, not a right sidebar a phone does not
    /// have, and Files and Links has a Files, a Links and an Attachments section.
    func testACompactWidthNamesTheLinksSheetAndFilesAndLinksHasItsThreeSections() async throws {
        let workspace = device.makeWorkspace()
        try await workspace.openFolderAsVault(try makeVault())
        let corePlugins = try phoneWidthSettings(of: workspace)
        try await open("Core Plugins", in: corePlugins)
        _ = try await elementScrolling(in: corePlugins, "a summary naming the Links and Outline sheet") { object in
            self.texts(of: object).contains { text in text.contains("in the Links and Outline sheet") }
        }
        try await scrollToEnd(in: corePlugins)
        XCTAssertNil(find(in: corePlugins) { object in self.texts(of: object).contains { text in text.contains("right sidebar") } },
                     "A phone has no right sidebar to name.")

        let filesAndLinks = try phoneWidthSettings(of: workspace)
        try await open("Files and Links", in: filesAndLinks)
        for header in ["Files", "Links", "Attachments"] {
            _ = try await elementScrolling(in: filesAndLinks, "the \(header) section") { object in
                object.accessibilityLabel == header
            }
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
            try await requireBarItem(titled: "Edit", in: controller, "the Edit button, which lets rows be dragged")
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

        let interfaceFont = try await elementOnScreen(in: controller, "the Interface Font row") {
            ($0.accessibilityLabel ?? "").hasPrefix("Interface Font") && $0.accessibilityTraits.contains(.button)
        }
        await follow(interfaceFont)
        try await requireBarItem(titled: "Choose an Installed Font…", in: controller, "the system font button")

        guard !isPhone else { return }
        // Beside the list, another page replaces the font list; it does not stay pushed on the new page.
        await tap(try await element(in: controller, "the Editor row") { $0.accessibilityLabel == "Editor" })
        _ = try await element(in: controller, "the Editor page") { ($0.accessibilityLabel ?? "").hasPrefix("Default View for New Notes") }
        // The old stack leaves the screen a moment after the new page arrives.
        try await waitUntil("the font list of the Appearance page is gone", timeoutSeconds: 10) {
            self.barItem(titled: "Choose an Installed Font…", in: controller) == nil
        }
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
        // Where the element found is the system's control itself, its step is the simulator's
        // accessibility bundle's to make. What such a step comes to is this value change, with
        // no finger on the control.
        let secondTry = ContinuousClock.now + .seconds(2)
        var isControlStepped = false
        try await waitUntil("the size is applied", timeoutSeconds: 10) {
            if !isControlStepped, ContinuousClock.now >= secondTry, let control = self.fontSizeControl(in: controller.view) {
                isControlStepped = true
                control.value += 1
                control.sendActions(for: .valueChanged)
            }
            return workspace.noteBaseFontSize > sizeBefore
        }
        if workspace.noteBaseFontSize <= sizeBefore { attachWhatIsOnScreen(in: controller, named: "the size is applied") }
        XCTAssertEqual(workspace.vaultAppearance.baseFontSize, workspace.noteBaseFontSize, "The step is saved, not only shown.")

        if isPhone {
            let pinch = try await elementScrolling(in: controller, "the quick adjustment text") { object in
                self.texts(of: object).contains { text in text.contains("Pinch a note with two fingers") }
            }
            XCTAssertFalse(texts(of: pinch).contains { text in text.contains("⌘") }, "A phone has no keyboard shortcuts to name.")
        }
    }

    private func fontSizeControl(in view: UIView) -> UISlider? {
        (view as? UISlider) ?? view.subviews.compactMap(fontSizeControl).first
    }

    // MARK: HUNT-255: Pencil sections for the iPad

    func testThePencilSectionsAreForTheIPadOnly() async throws {
        let workspace = device.makeWorkspace()
        workspace.setCorePluginEnabled(.drawings, true)
        let controller = try settings(of: workspace)
        try await open("Pencil Drawings", in: controller)

        if isPhone {
            _ = try await element(in: controller, "the Paper section") { $0.accessibilityLabel == "Paper" }
            try await scrollToEnd(in: controller)
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

        let themeLink = try await elementOnScreen(in: controller, "the Theme row") {
            ($0.accessibilityLabel ?? "").hasPrefix("Theme") && $0.accessibilityTraits.contains(.button)
        }
        await follow(themeLink)
        let themeRow = try await element(in: controller, "the Other theme") { $0.accessibilityLabel == "Other" }
        await askToDelete(themeRow, in: controller)

        _ = try await element(in: controller, "the question") { $0.accessibilityLabel == "Delete “Other”?" }
        XCTAssertTrue(FileManager.default.fileExists(atPath: vault.appendingPathComponent(".obsidian/themes/Other/theme.css").path), "Nothing is deleted before the person agrees.")
    }

    /// Presses a row's swipe action Delete: from the action VoiceOver is offered, on the element or
    /// on the list's cell around it, else with a swipe as a finger makes it (UIKit's own gesture).
    private func askToDelete(_ row: NSObject, in controller: UIViewController) async {
        if let action = deleteAction(of: row) {
            if let handler = action.actionHandler {
                if handler(action) { return }
            } else if let target = action.target as? NSObject {
                _ = target.perform(action.selector, with: action)
                return
            }
        }
        guard let window else { return XCTFail("No window.") }
        let frame = row.accessibilityFrame
        await SynthesizedTouches(window: window).drag(from: CGPoint(x: frame.maxX - 12, y: frame.midY), to: CGPoint(x: frame.minX + 12, y: frame.midY))
        // A full swipe has pressed Delete; a shorter one leaves it showing.
        if let button = find(in: controller, matching: { $0.accessibilityLabel == "Delete" }), !button.accessibilityActivate() { await tap(button) }
    }

    private func deleteAction(of row: NSObject) -> UIAccessibilityCustomAction? {
        func deleteAction(on object: NSObject) -> UIAccessibilityCustomAction? {
            object.accessibilityCustomActions?.first { action in action.name.hasPrefix("Delete") }
        }
        if let action = deleteAction(on: row) { return action }
        let frame = row.accessibilityFrame
        var view = window?.hitTest(CGPoint(x: frame.midX, y: frame.midY), with: nil)
        while let current = view {
            if let action = deleteAction(on: current) { return action }
            view = current.superview
        }
        return nil
    }
}

#endif
