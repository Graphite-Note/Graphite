/**
 * File: NoteIconEditingTests.swift
 * --------------------------------
 * Layer: Tests
 * Description: Setting or removing a note's icon rewrites only its frontmatter, keeps every other property as written,
 *              and moves the selection with the text after it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import XCTest
@testable import GraphiteCore

final class NoteIconEditingTests: XCTestCase {
    private func applying(_ edit: MarkdownTextEdit?, to text: String) -> String {
        guard let edit else { return text }
        return (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
    }

    func testAnIconIsAddedToANoteWithoutFrontmatter() throws {
        let note = "# Lecture 3\n\nText."
        let edit = try NoteIconEditing.edit(setting: .emoji("📚"), in: note, selection: NSRange(location: 2, length: 0))
        XCTAssertEqual(applying(edit, to: note), "---\nicon: 📚\n---\n# Lecture 3\n\nText.")
        XCTAssertEqual(edit?.selectionAfter, NSRange(location: 2 + ("---\nicon: 📚\n---\n" as NSString).length, length: 0))
    }

    func testAnIconIsWrittenAmongTheOtherPropertiesAsTheyAre() throws {
        let note = "---\ntags: [physics, \"exam\"]\ncourse: EE330\n---\nBody stays.\n"
        let edited = applying(try NoteIconEditing.edit(setting: .symbol(systemName: "atom"), in: note, selection: NSRange()), to: note)
        XCTAssertTrue(edited.hasSuffix("---\nBody stays.\n"))
        XCTAssertTrue(edited.contains("course: EE330"))
        XCTAssertTrue(edited.contains("icon: LiAtom"), "A chosen symbol is written as Iconize's Lucide name.")
        let yamlRange = NSRange(location: 4, length: FrontmatterLocator.length(in: edited as NSString) - 8)
        let properties = NoteProperties.parse((edited as NSString).substring(with: yamlRange))
        XCTAssertEqual(properties?.first { property in property.key == "tags" }?.value, .list(["physics", "exam"]))
    }

    func testAnIconIsReplacedAndRemoved() throws {
        let note = "---\nicon: 🧪\naliases: [Lab]\n---\nText"
        let replaced = applying(try NoteIconEditing.edit(setting: .emoji("📐"), in: note, selection: NSRange()), to: note)
        XCTAssertTrue(replaced.contains("icon: 📐"))
        XCTAssertFalse(replaced.contains("🧪"))
        let removed = applying(try NoteIconEditing.edit(setting: nil, in: replaced, selection: NSRange()), to: replaced)
        XCTAssertFalse(removed.contains("icon"))
        XCTAssertTrue(removed.hasSuffix("---\nText"))
    }

    func testTheSameIconIsNoEdit() throws {
        XCTAssertNil(try NoteIconEditing.edit(setting: .emoji("🧪"), in: "---\nicon: 🧪\n---\nText", selection: NSRange()))
        XCTAssertNil(try NoteIconEditing.edit(setting: nil, in: "Text", selection: NSRange()))
    }

    func testFrontmatterThatIsNotYAMLIsLeftAlone() {
        XCTAssertThrowsError(try NoteIconEditing.edit(setting: .emoji("📚"), in: "---\n: [unclosed\n---\nText", selection: NSRange()))
    }

    func testTheIconIsReadFromTheNotesFrontmatter() {
        XCTAssertEqual(NoteIconEditing.icon(in: "---\nIcon: LiBookOpen\n---\nText"), .symbol(systemName: "book"))
        XCTAssertNil(NoteIconEditing.icon(in: "icon: 📚"), "Not frontmatter.")
        XCTAssertNil(NoteIconEditing.icon(in: "---\nicon: [a, b]\n---\n"), "A list names no icon.")
    }
}
