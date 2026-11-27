/**
 * File: PDFMarkupTextFormatControlsTests.swift
 * --------------------------------------------
 * Layer: Tests
 * Description: The markup row's text style controls acting on the selected text box: each button and segment
 *              pressed through AppKit, and each menu's items chosen, changing the box's record as one step each.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 27/11/2026
 */

#if os(macOS)
import XCTest
import AppKit
import SwiftUI
import PDFKit
import GraphiteCore
import GraphiteApple
@testable import GraphiteUI
import GraphiteTestSupport

@MainActor
final class PDFMarkupTextFormatControlsTests: XCTestCase {
    private var openedHarness: MacPDFPageToolHarness?

    override func setUp() async throws {
        try await super.setUp()
        openedHarness = try await MacPDFPageToolHarness.open(for: self, prefix: "PDFMarkupTextFormatControls")
    }

    private func box(_ fixture: MacPDFPageToolHarness) throws -> PDFTextBox {
        try XCTUnwrap(fixture.session.textBoxes(on: fixture.page).first)
    }

    /// A box typed and left, then selected by a click, as the row formats it.
    private func selectedBox(in fixture: MacPDFPageToolHarness) throws -> PDFTextBox {
        fixture.choose(.textBox)
        try fixture.drag(through: [CGPoint(x: 80, y: 500)])
        let textView = try XCTUnwrap(fixture.window.firstResponder as? NSTextView)
        textView.insertText("Gain stage", replacementRange: textView.selectedRange())
        try fixture.drag(through: [CGPoint(x: 300, y: 100)])
        let placed = try box(fixture)
        try fixture.drag(through: [placed.middle])
        XCTAssertEqual(fixture.session.textBoxActivity.selection?.boxName, placed.name, "A click selects the box.")
        return placed
    }

    /// The row's text controls for the session as it is now, in a window of their own.
    private func hostControls(of fixture: MacPDFPageToolHarness, isFolded: Bool) -> NSView {
        let hosting = NSHostingView(rootView: PDFMarkupTextFormatControls(source: PDFMarkupTextFormatSource(session: fixture.session), isFolded: isFolded))
        hosting.frame = CGRect(x: 0, y: 0, width: 900, height: 40)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView = hosting
        window.showInvisibly()
        hosting.layoutSubtreeIfNeeded()
        addTeardownBlock { window.orderOut(nil) }
        return hosting
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { subview in [subview] + descendants(of: subview) }
    }

    /// The hosted controls, in the order the row shows them.
    private struct Controls {
        let menuButtons: [NSView]
        let popUps: [NSPopUpButton]
        let buttons: [NSButton]
        let segmented: NSSegmentedControl?
    }

    private func controls(of fixture: MacPDFPageToolHarness, isFolded: Bool) -> Controls {
        let views = descendants(of: hostControls(of: fixture, isFolded: isFolded))
        return Controls(menuButtons: views.filter { view in String(describing: type(of: view)) == "KeyViewProxy" },
                        popUps: views.compactMap { view in view as? NSPopUpButton },
                        buttons: views.compactMap { view in view as? NSButton }.filter { button in !(button is NSPopUpButton) },
                        segmented: views.lazy.compactMap { view in view as? NSSegmentedControl }.first)
    }

    /// Runs `action` as one user action and checks it is one Format Text step.
    private func formatStep(_ fixture: MacPDFPageToolHarness, file: StaticString = #filePath, line: UInt = #line, _ action: () throws -> Void) rethrows {
        let before = try? box(fixture)
        fixture.session.undoManager.beginUndoGrouping()
        try action()
        fixture.session.undoManager.endUndoGrouping()
        XCTAssertNotEqual(try? box(fixture), before, "The control changed the box.", file: file, line: line)
        XCTAssertEqual(fixture.session.undoManager.undoActionName, "Format Text", file: file, line: line)
    }

    /// Chooses the item titled `title` of a menu's items, as the menu's button does: its change handed to the box.
    private func choose(_ title: String, of items: [PDFMarkupTextFormatChoice], in fixture: MacPDFPageToolHarness,
                        file: StaticString = #filePath, line: UInt = #line) throws {
        let item = try XCTUnwrap(items.first { item in item.title == title }, "\(title) in \(items.map(\.title))", file: file, line: line)
        let source = PDFMarkupTextFormatSource(session: fixture.session)
        let applyToBox = try XCTUnwrap(source.applyToBox, "The row formats the selected box.", file: file, line: line)
        formatStep(fixture, file: file, line: line) { applyToBox(item.change) }
    }

    /// Each control of the row's Text Box choices changes the selected box as one Format Text step. Its
    /// buttons and segments are pressed through AppKit; its pop-up menus are never opened (AppKit would
    /// wait in a menu's loop for a person), and their items, the list the menus show, are chosen as a
    /// menu item's button chooses them.
    func testEachTextStyleControlOfTheRowFormatsTheSelectedBox() throws {
        let fixture = try XCTUnwrap(openedHarness)
        let placed = try selectedBox(in: fixture)
        var row = controls(of: fixture, isFolded: false)
        XCTAssertEqual(row.menuButtons.count, 2, "Font and Size")
        XCTAssertEqual(row.popUps.count, 2, "Text Color and Fill")
        XCTAssertEqual(row.buttons.count, 4, "Bold, Italic, Underline and Border")
        XCTAssertEqual(row.segmented?.segmentCount, 4, "Left, Center, Right and Justified")

        XCTAssertEqual(PDFMarkupTextFormatMenus.fonts(current: placed.leadingAttributes.fontFamily).map(\.title), PDFTextBoxFonts.offeredFamilies)
        XCTAssertEqual(PDFMarkupTextFormatMenus.fonts(current: "Futura").first?.title, "Futura", "Another family shows first, ticked.")
        try choose("Georgia", of: PDFMarkupTextFormatMenus.fonts(current: placed.leadingAttributes.fontFamily), in: fixture)
        XCTAssertEqual(try box(fixture).leadingAttributes.fontFamily, "Georgia")
        try choose("24 pt", of: PDFMarkupTextFormatMenus.sizes, in: fixture)
        XCTAssertEqual(try box(fixture).leadingAttributes.fontSize, 24)

        row = controls(of: fixture, isFolded: false)
        formatStep(fixture) { row.buttons[1].performClick(nil) }
        XCTAssertTrue(try box(fixture).leadingAttributes.isItalic, "Italic")
        row = controls(of: fixture, isFolded: false)
        formatStep(fixture) { row.buttons[2].performClick(nil) }
        XCTAssertTrue(try box(fixture).leadingAttributes.isUnderlined, "Underline")

        let colors = PDFMarkupTextFormatMenus.colors(storedPalette: nil,
                                                     current: try box(fixture).leadingAttributes.color)
        let otherColor = try XCTUnwrap(colors.dropFirst().first, "Black and the favourite colours")
        try choose(otherColor.title, of: colors, in: fixture)
        guard case .color(let chosenColor) = otherColor.change else { return XCTFail("The colour menu's items set the colour.") }
        XCTAssertEqual(try box(fixture).leadingAttributes.color, chosenColor)

        try choose("Yellow Fill", of: PDFMarkupTextFormatMenus.fills, in: fixture)
        XCTAssertEqual(try box(fixture).style.fillColor, PDFTextColor(red: 1, green: 0.96, blue: 0.62))

        row = controls(of: fixture, isFolded: false)
        let alignment = try XCTUnwrap(row.segmented)
        let alignmentAction = try XCTUnwrap(alignment.action)
        formatStep(fixture) {
            alignment.selectedSegment = 1
            NSApp.sendAction(alignmentAction, to: alignment.target, from: alignment)
        }
        XCTAssertEqual(try box(fixture).style.alignment, .center)

        row = controls(of: fixture, isFolded: false)
        formatStep(fixture) { row.buttons[3].performClick(nil) }
        XCTAssertEqual(try box(fixture).style.borderWidth, PDFTextBoxFormatChange.standardBorderWidth)

        // Folded, alignment, fill and border are one menu.
        XCTAssertEqual(controls(of: fixture, isFolded: true).popUps.count, 2, "Text Color and Box Format")
        try choose("Right", of: PDFMarkupTextFormatMenus.alignments, in: fixture)
        XCTAssertEqual(try box(fixture).style.alignment, .right)
        try choose("No Fill", of: PDFMarkupTextFormatMenus.fills, in: fixture)
        XCTAssertNil(try box(fixture).style.fillColor)

        for _ in 0..<10 { fixture.session.undoManager.undo() }
        XCTAssertEqual(try box(fixture), placed, "Each choice was one step: ten undos give the box back as placed.")
    }
}
#endif
