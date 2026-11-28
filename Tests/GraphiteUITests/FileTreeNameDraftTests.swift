/**
 * File: FileTreeNameDraftTests.swift
 * ----------------------------------
 * Layer: Tests
 * Description: The decisions of a name field in the file tree's row: what it starts with, the names it refuses, and
 *              what Return, Escape and clicking elsewhere do.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 27/11/2026
 */

import XCTest
import GraphiteCore
@testable import GraphiteUI

final class FileTreeNameDraftTests: XCTestCase {
    private func newItem(_ kind: FileTreeCreatableKind, in folder: String = "Course", names: [String] = []) throws -> FileTreeNameDraft {
        FileTreeNameDraft(subject: .newItem(kind, in: try VaultPath(folder)), namesInFolder: names)
    }

    private func existing(_ path: String, isFolder: Bool = false, names: [String] = []) throws -> FileTreeNameDraft {
        FileTreeNameDraft(subject: .existingItem(try VaultPath(path), isFolder: isFolder), namesInFolder: names)
    }

    /// A new item's field starts empty with "Untitled" as its hint; Return on it makes "Untitled", as Obsidian's new
    /// note does, while a click elsewhere on an empty field makes nothing.
    func testAnEmptyNewItemIsUntitledOnReturnAndNothingWhenLeft() throws {
        let draft = try newItem(.note)
        XCTAssertEqual(draft.initialText, "")
        XCTAssertEqual(draft.placeholder, "Untitled")
        XCTAssertNil(draft.problem(typed: ""))
        XCTAssertEqual(draft.outcome(typed: "  ", endedBy: .returnKey), .create(.note, name: "Untitled", in: try VaultPath("Course")))
        XCTAssertEqual(draft.outcome(typed: "", endedBy: .focusLeft), .cancel)
        XCTAssertEqual(draft.outcome(typed: "Week 3", endedBy: .escapeKey), .cancel)
    }

    /// A typed name is kept on Return and on a click elsewhere, as in VSCodium.
    func testATypedNameIsCreatedOnReturnAndWhenLeft() throws {
        let draft = try newItem(.canvas)
        let expected = FileTreeNamingOutcome.create(.canvas, name: "Map", in: try VaultPath("Course"))
        XCTAssertEqual(draft.outcome(typed: " Map ", endedBy: .returnKey), expected)
        XCTAssertEqual(draft.outcome(typed: "Map", endedBy: .focusLeft), expected)
    }

    /// A name already in the folder, compared without case and with the new file's extension, is refused under the
    /// field; Return keeps the field open, and leaving it makes nothing.
    func testANameAlreadyInTheFolderIsRefused() throws {
        let draft = try newItem(.note, names: ["Week 1.md", "Week 2", "Map.canvas"])
        XCTAssertEqual(draft.problem(typed: "week 1"), "“week 1” is already in this folder. Choose a different name.")
        XCTAssertNil(draft.outcome(typed: "week 1", endedBy: .returnKey))
        XCTAssertEqual(draft.outcome(typed: "week 1", endedBy: .focusLeft), .cancel)
        // A folder called Week 2 is not a note called Week 2, and a canvas called Map is not a note called Map.
        XCTAssertNil(draft.problem(typed: "Week 2"))
        XCTAssertNil(draft.problem(typed: "Map"))
        XCTAssertNotNil(try newItem(.folder, names: ["Week 2"]).problem(typed: "WEEK 2"))
    }

    /// A note's name may not hold what breaks links; a base's may.
    func testANotesNameKeepsLinksWorking() throws {
        XCTAssertNotNil(try newItem(.note).problem(typed: "C# notes"))
        XCTAssertNil(try newItem(.base).problem(typed: "C# notes"))
        XCTAssertNotNil(try newItem(.folder).problem(typed: "a/b"))
    }

    /// A folder made with nothing typed gets the first "Untitled" the folder does not have: the store refuses a folder
    /// that exists, while it numbers files itself.
    func testAnUntitledFolderIsNumberedPastTheOnesThere() throws {
        let draft = try newItem(.folder, in: "", names: ["Untitled", "untitled 1", "Notes.md"])
        XCTAssertEqual(draft.outcome(typed: "", endedBy: .returnKey), .create(.folder, name: "Untitled 2", in: .root))
        XCTAssertEqual(try newItem(.note, names: ["Untitled.md"]).outcome(typed: "", endedBy: .returnKey),
                       .create(.note, name: "Untitled", in: try VaultPath("Course")))
    }

    /// A rename starts with the name without its extension, a typed extension is not doubled, and the same name is no
    /// rename.
    func testARenameStartsWithTheNameAndKeepsTheExtension() throws {
        let draft = try existing("Course/Lecture.pdf", names: ["Lecture.pdf", "Slides.pdf"])
        XCTAssertEqual(draft.initialText, "Lecture")
        XCTAssertEqual(draft.keptExtensionSuffix, ".pdf")
        XCTAssertEqual(draft.outcome(typed: "Lecture 2.pdf", endedBy: .returnKey), .rename(try VaultPath("Course/Lecture.pdf"), to: "Lecture 2"))
        XCTAssertEqual(draft.outcome(typed: "Lecture", endedBy: .returnKey), .cancel)
        XCTAssertNotNil(draft.problem(typed: "slides"))
        XCTAssertNil(try existing("Course/Lecture.md").keptExtensionSuffix, "A note's row hides .md, and so does its field.")
    }

    /// Changing only the case of a name is a rename, not a clash with the item itself.
    func testACaseOnlyRenameIsAllowed() throws {
        let draft = try existing("Course/lecture.md", names: ["lecture.md"])
        XCTAssertNil(draft.problem(typed: "Lecture"))
        XCTAssertEqual(draft.outcome(typed: "Lecture", endedBy: .returnKey), .rename(try VaultPath("Course/lecture.md"), to: "Lecture"))
    }

    /// An emptied rename shows why; Return keeps the field, and leaving it keeps the old name.
    func testAnEmptiedRenameKeepsTheOldName() throws {
        let draft = try existing("Course", isFolder: true, names: ["Course", "Other"])
        XCTAssertEqual(draft.initialText, "Course")
        XCTAssertNil(draft.keptExtensionSuffix)
        XCTAssertEqual(draft.problem(typed: ""), "Enter a name.")
        XCTAssertNil(draft.outcome(typed: "", endedBy: .returnKey))
        XCTAssertEqual(draft.outcome(typed: "", endedBy: .focusLeft), .cancel)
        XCTAssertNotNil(draft.problem(typed: "other"))
    }

    /// A notebook keeps its sheet, which chooses its paper, and a course its sheet, which makes its page.
    func testANotebookAndACourseAreNotNamedInARow() {
        XCTAssertNil(FileTreeCreatableKind(.notebook))
        XCTAssertNil(FileTreeCreatableKind(.course))
        XCTAssertEqual(FileTreeCreatableKind(.base), .base)
    }
}
