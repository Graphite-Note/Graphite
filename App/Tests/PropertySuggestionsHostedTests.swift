/**
 * File: PropertySuggestionsHostedTests.swift
 * ------------------------------------------
 * Layer: Tests
 * Description: The Properties panel's suggestions on the iPad and the iPhone: a new property's name with its type, a
 *              tags item from the vault's tags without the note's own, and the frontmatter written once when one is chosen.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 17/11/2026
 */

#if os(iOS)
import XCTest
import SwiftUI
import GraphiteCore
@testable import GraphiteUI

/// `Docs/Property-and-tag-completion-todo.md`, section 1, with suggestions given by the test, as the vault's index would.
@MainActor
final class PropertySuggestionsHostedTests: SettingsHostedTestCase {
    private var committed: [[NoteProperty]] = []

    private func suggestion(_ text: String, _ fileCount: Int, _ systemImage: String) -> PropertySuggestions.Suggestion {
        PropertySuggestions.Suggestion(text: text, fileCount: fileCount, systemImage: systemImage)
    }

    private var lookup: PropertySuggestionLookup {
        PropertySuggestionLookup(names: { query, written in
            [self.suggestion("course", 40, "text.alignleft"), self.suggestion("due", 12, "calendar"), self.suggestion("tags", 90, "tag")]
                .filter { name in !written.contains(name.text) && (query.isEmpty || name.text.localizedCaseInsensitiveContains(query)) }
        }, values: { name, query, written in
            guard name == "tags" else { return [] }
            return [self.suggestion("eth/vlsi", 30, "number"), self.suggestion("exam", 8, "number")]
                .filter { tag in !written.contains(tag.text) && (query.isEmpty || tag.text.localizedCaseInsensitiveContains(query)) }
        }, type: { name in name == "due" ? .date : (name == "tags" ? .tags : .text) },
           notes: { query in
            [self.suggestion("Lectures/VLSI 1", 0, "doc.text")].filter { note in note.text.localizedCaseInsensitiveContains(query) }
        })
    }

    private func panel(_ properties: [NoteProperty]) throws -> UIHostingController<AnyView> {
        try host(ScrollView {
            PropertiesPanel(properties: properties, update: { updated in self.committed.append(updated) }, suggestions: lookup).padding()
        }, size: isPhone ? nil : CGSize(width: 600, height: 700))
    }

    private func type(_ text: String, in field: UITextField) {
        for character in text { field.insertText(String(character)) }
    }

    func testANewPropertysNameIsSuggestedWithItsTypeAndChoosingItAddsTheTypesField() async throws {
        let controller = try panel([NoteProperty(key: "tags", value: .list(["exam"]))])
        let addProperty = try await element(in: controller, "Add Property") { object in object.accessibilityLabel == "Add Property" }
        XCTAssertTrue(addProperty.accessibilityActivate())
        var nameField: UITextField?
        try await waitUntil("the name field takes the typing", timeoutSeconds: 10) {
            nameField = self.textFields(in: controller.view).first { field in field.placeholder == "Property name" && field.isFirstResponder }
            return nameField != nil
        }
        type("du", in: try XCTUnwrap(nameField))
        let due = try await element(in: controller, "the suggested name") { object in object.accessibilityLabel == "due" }
        XCTAssertEqual(due.accessibilityValue, "12 notes")
        XCTAssertNil(find(in: controller) { object in object.accessibilityLabel == "tags" && object.accessibilityValue == "90 notes" },
                     "A name the note has is not suggested.")
        attachWhatIsOnScreen(in: controller, named: "The name suggestions")
        XCTAssertTrue(due.accessibilityActivate())
        try await waitUntil("the property is added", timeoutSeconds: 10) { !self.committed.isEmpty }
        XCTAssertEqual(committed.count, 1, "The frontmatter is written once.")
        let added = try XCTUnwrap(committed.last?.last)
        XCTAssertEqual(added.key, "due")
        guard case .date = added.value else { return XCTFail("A date property gets the date field: \(added.value)") }
    }

    func testATagsItemSuggestsTheVaultsTagsWithoutTheNotesOwnAndChoosingAddsIt() async throws {
        let controller = try panel([NoteProperty(key: "tags", value: .list(["exam"]))])
        var itemField: UITextField?
        try await waitUntil("the list's field", timeoutSeconds: 10) {
            itemField = self.textFields(in: controller.view).first { field in field.placeholder == "" || field.placeholder == nil }
            return itemField != nil
        }
        let field = try XCTUnwrap(itemField)
        XCTAssertTrue(field.becomeFirstResponder())
        type("e", in: field)
        _ = try await element(in: controller, "the suggested tag") { object in object.accessibilityLabel == "eth/vlsi" }
        XCTAssertNil(find(in: controller) { object in object.accessibilityLabel == "exam" && object.accessibilityValue == "8 notes" },
                     "A tag the note lists is not suggested.")
        let tag = try XCTUnwrap(find(in: controller) { object in object.accessibilityLabel == "eth/vlsi" })
        XCTAssertTrue(tag.accessibilityActivate())
        try await waitUntil("the tag is added", timeoutSeconds: 10) { !self.committed.isEmpty }
        XCTAssertEqual(committed.count, 1, "The frontmatter is written once.")
        XCTAssertEqual(committed.last?.first?.value, .list(["exam", "eth/vlsi"]))
        XCTAssertEqual(field.text, "", "The field is left empty for the next tag.")
    }
    func testALinkTypedInAnAliasesItemSuggestsNotesAndChoosingWritesTheLink() async throws {
        let controller = try panel([NoteProperty(key: "aliases", value: .list([]))])
        var itemField: UITextField?
        try await waitUntil("the list's field", timeoutSeconds: 10) {
            itemField = self.textFields(in: controller.view).first { field in field.placeholder == "Empty" }
            return itemField != nil
        }
        let field = try XCTUnwrap(itemField)
        XCTAssertTrue(field.becomeFirstResponder())
        type("[[VLSI", in: field)
        let note = try await element(in: controller, "the suggested note") { object in object.accessibilityLabel == "Lectures/VLSI 1" }
        XCTAssertTrue(note.accessibilityActivate())
        try await waitUntil("the link is added", timeoutSeconds: 10) { !self.committed.isEmpty }
        XCTAssertEqual(committed.last?.first?.value, .list(["[[Lectures/VLSI 1]]"]), "The link is closed, as Obsidian writes it.")
    }

    // MARK: Section 3: the Bases property editor sheet

    func testTheBasePropertyEditorSuggestsTheVaultsValuesAndSavesTheChosenOne() async throws {
        var saved: [PropertyValue?] = []
        let request = BaseEditRequest(path: try VaultPath("Lectures/VLSI 1.md"), property: .note("tags"), displayName: "tags", kind: .list,
                                      currentValue: .list([]))
        let controller = try host(BasePropertyEditorSheet(request: request) { value in saved.append(value); return nil }
            .environment(\.propertySuggestionLookup, lookup))
        var listField: (UIView & UIKeyInput)?
        try await waitUntil("the list's field", timeoutSeconds: 10) {
            listField = self.textInputs(in: controller.view).first
            return listField != nil
        }
        let field = try XCTUnwrap(listField)
        XCTAssertTrue(field.becomeFirstResponder())
        field.insertText("exam\neth")
        let tag = try await element(in: controller, "the suggested tag") { object in object.accessibilityLabel == "eth/vlsi" }
        XCTAssertNil(find(in: controller) { object in object.accessibilityLabel == "exam" && object.accessibilityValue == "8 notes" },
                     "The list's other line is not suggested again.")
        XCTAssertTrue(tag.accessibilityActivate())
        try await requireBarItem(titled: "Save", in: controller, "the Save button")
        let save = try XCTUnwrap(barItem(titled: "Save", in: controller))
        if let saveItem = save as? UIBarButtonItem, let action = saveItem.action { UIApplication.shared.sendAction(action, to: saveItem.target, from: saveItem, for: nil) }
        else { XCTAssertTrue(save.accessibilityActivate()) }
        try await waitUntil("the value is saved", timeoutSeconds: 10) { !saved.isEmpty }
        XCTAssertEqual(saved.first ?? nil, .list(["exam", "eth/vlsi"]))
    }

    /// The views typing goes into: a text field, or a field of several lines.
    private func textInputs(in view: UIView) -> [UIView & UIKeyInput] {
        (view as? (UIView & UIKeyInput)).map { input in [input] } ?? view.subviews.flatMap(textInputs)
    }
}
#endif
