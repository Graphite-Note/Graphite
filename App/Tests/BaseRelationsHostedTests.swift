/**
 * File: BaseRelationsHostedTests.swift
 * ------------------------------------
 * Layer: Tests
 * Description: Relations, New and rollups of Bases on the iPad and the iPhone: the relation picker in the property
 *              sheet, New in a view embedded in a course note, and a course page's views and rollups drawn.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

#if os(iOS)
import XCTest
import SwiftUI
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI

/// `Docs/Bases-relations-todo.md`, sections 1 to 4, through the views the app shows.
@MainActor
final class BaseRelationsHostedTests: SettingsHostedTestCase {
    private var vault: TemporaryVault!
    private var index: VaultIndex!
    private var store: VaultStore!
    private var shownNotes: [VaultPath] = []

    private func openVault(_ files: [String: String]) async throws {
        vault = try TemporaryVault.make(prefix: "BaseRelationsHosted", files: files, for: self)
        let indexFolder = try TemporaryVault.make(prefix: "BaseRelationsHostedIndex", for: self).root
        index = try VaultIndex(databaseURL: indexFolder.appendingPathComponent("index.sqlite"))
        store = VaultStore(root: vault.root)
        _ = try await index.reconcile(root: vault.root)
    }

    private var services: BaseNoteServices {
        BaseNoteServices(linkTarget: { path, _ in path.stem }, searchNotes: { _, _ in [] }, fillTemplate: { text, _ in text },
                         newNoteLocation: .vaultFolder, vaultPropertyTypes: { ["course": .multitext] },
                         showNewNote: { [weak self] path in self?.shownNotes.append(path) })
    }

    private func press(_ title: String, in controller: UIViewController) async throws {
        try await requireBarItem(titled: title, in: controller, "the \(title) button")
        let item = try XCTUnwrap(barItem(titled: title, in: controller))
        if let barButton = item as? UIBarButtonItem, let action = barButton.action {
            UIApplication.shared.sendAction(action, to: barButton.target, from: barButton, for: nil)
        } else {
            XCTAssertTrue(item.accessibilityActivate())
        }
    }

    // MARK: Section 1: the relation picker

    func testTheSheetOfARelationOpensOnThePickerAndChoosingANoteSavesItsLink() async throws {
        let vlsi = try VaultPath("Courses/VLSI 3.md")
        let signals = try VaultPath("Courses/Signals.md")
        var saved: [PropertyValue?] = []
        let editing = BaseRelationEditing(
            isRelation: { true },
            currentChoices: { [BaseRelationChoice(writtenItem: "[[VLSI 3]]", path: vlsi)] },
            candidates: { query in
                [BaseRelationCandidate(path: vlsi, source: .linked), BaseRelationCandidate(path: signals, source: .sameFolder)]
                    .filter { candidate in query.isEmpty || candidate.title.localizedCaseInsensitiveContains(query) }
            },
            linkTarget: { path in path.stem }, shape: .list)
        let request = BaseEditRequest(path: try VaultPath("Assignments/Lab 1.md"), property: .note("course"), displayName: "course", kind: .list,
                                      currentValue: .list([.link(BaseLink(target: "VLSI 3"))]))
        let controller = try host(BasePropertyEditorSheet(request: request, relation: editing) { value in saved.append(value); return nil },
                                  size: isPhone ? nil : CGSize(width: 600, height: 800))
        _ = try await element(in: controller, "the linked note") { object in object.accessibilityLabel == "Remove VLSI 3" }
        let signalsRow = try await element(in: controller, "the offered note Signals") { object in
            (object.accessibilityLabel ?? "").hasPrefix("Signals") && object.accessibilityTraits.contains(.button)
        }
        XCTAssertTrue(signalsRow.accessibilityActivate())
        _ = try await element(in: controller, "Signals chosen") { object in object.accessibilityLabel == "Remove Signals" }
        attachWhatIsOnScreen(in: controller, named: "the relation picker with two notes")
        try await press("Save", in: controller)
        try await waitUntil("the links are saved", timeoutSeconds: 10) { !saved.isEmpty }
        XCTAssertEqual(saved.first ?? nil, .list(["[[VLSI 3]]", "[[Signals]]"]))
    }

    // MARK: Sections 3 and 4: New in a view embedded in a course note, and the course page drawn

    private static let courseVault: [String: String] = [
        "Courses/VLSI 3.md": "---\ntype: course\n---\n",
        "Courses/Signals.md": "---\ntype: course\n---\n",
        "Courses/Assignments/Lab 1.md": "---\ncourse:\n  - \"[[VLSI 3]]\"\ndone: true\nweight: 10\n---\n",
        "Courses/Assignments/Lab 2.md": "---\ncourse:\n  - \"[[VLSI 3]]\"\ndone: false\nweight: 30\n---\n",
        "Courses/Assignments/Essay.md": "---\ncourse:\n  - \"[[Signals]]\"\ndone: true\nweight: 50\n---\n",
        "Courses/Assignments.base": """
            filters: file.inFolder("Courses/Assignments")
            views:
              - type: table
                name: This course
                filters: 'list(course).contains(this)'
                order: [file.name, weight, done]
              - type: cards
                name: Cards
                filters: 'list(course).contains(this)'
              - type: list
                name: List
                filters: 'list(course).contains(this)'
            """,
        "Courses/Courses.base": """
            filters: type == "course"
            formulas:
              assignments: file.backlinks.map(value.asFile()).filter(value).filter(list(value.properties.course).contains(file))
              done: formula.assignments.filter(value.properties.done == true).length
              progress: if(formula.assignments.length == 0, 0, (formula.done / formula.assignments.length * 100).round())
            views:
              - type: table
                name: Courses
                order: [file.name, formula.done, formula.progress]
            """,
    ]

    private func embed(_ base: String, view: String, in note: String) throws -> some View {
        EmbeddedBaseView(basePath: try VaultPath(base), viewName: view, embeddingNote: try VaultPath(note), store: store, index: index, open: { _ in })
            .environment(\.baseNoteServices, services)
    }

    func testNewInAViewEmbeddedInACourseNoteMakesANoteLinkedToThatCourse() async throws {
        try await openVault(Self.courseVault)
        let controller = try host(ScrollView { try? embed("Courses/Assignments.base", view: "This course", in: "Courses/VLSI 3.md").padding() },
                                  size: isPhone ? nil : CGSize(width: 700, height: 700))
        _ = try await element(in: controller, "the course's own assignment") { object in (object.accessibilityLabel ?? "").contains("Lab 2") }
        XCTAssertNil(find(in: controller) { object in (object.accessibilityLabel ?? "").contains("Essay") }, "Another course's assignment is not shown.")
        let new = try await element(in: controller, "the New button") { object in object.accessibilityLabel == "New" }
        XCTAssertTrue(new.accessibilityActivate())
        try await press("Create", in: controller)
        try await waitUntil("the note is made", timeoutSeconds: 10) { !self.shownNotes.isEmpty }
        XCTAssertEqual(shownNotes.map(\.rawValue), ["Courses/Assignments/Untitled.md"])
        let text = try String(contentsOf: vault.root.appendingPathComponent("Courses/Assignments/Untitled.md"), encoding: .utf8)
        XCTAssertEqual(text, "---\ncourse:\n  - \"[[VLSI 3]]\"\nweight:\ndone:\n---\n")
    }

    /// `this` in an embed is the embedding note in a table, cards and a list, and a base of courses shows each course's
    /// rollups. The window's picture is attached to look at.
    func testACoursePageShowsItsOwnAssignmentsInEveryViewAndTheCoursesShowTheirRollups() async throws {
        try await openVault(Self.courseVault)
        let page = VStack(spacing: 16) {
            try? embed("Courses/Courses.base", view: "Courses", in: "Courses/VLSI 3.md")
            try? embed("Courses/Assignments.base", view: "This course", in: "Courses/VLSI 3.md")
            try? embed("Courses/Assignments.base", view: "Cards", in: "Courses/Signals.md")
            try? embed("Courses/Assignments.base", view: "List", in: "Courses/Signals.md")
        }
        let controller = try host(ScrollView { page.padding() }, size: isPhone ? nil : CGSize(width: 820, height: 1_180))
        _ = try await element(in: controller, "the table's assignment") { object in (object.accessibilityLabel ?? "").contains("Lab 1") }
        _ = try await element(in: controller, "VLSI 3's percent done") { object in (object.accessibilityLabel ?? "") == "50" }
        try await waitUntil("Signals' cards and list", timeoutSeconds: 10) {
            self.accessibilityElements(in: controller.view).filter { object in (object.accessibilityLabel ?? "").contains("Essay") }.count >= 2
        }
        if let window {
            let picture = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            let attachment = XCTAttachment(image: picture)
            attachment.name = "A course page and the courses with their rollups"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
#endif
