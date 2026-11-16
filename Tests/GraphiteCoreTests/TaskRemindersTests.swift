/**
 * File: TaskRemindersTests.swift
 * ------------------------------
 * Layer: Tests
 * Description: Task lines with the Tasks plugin's fields, the block ID that links a task to its reminder, ticking a
 *              task, the reminder's link back to it, which side of a link changed, and reminders as tasks.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

import XCTest
@testable import GraphiteCore

final class TaskRemindersTests: XCTestCase {
    private let november12 = CalendarDay(year: 2026, month: 11, day: 12)

    // MARK: Reading a task

    func testATaskLineGivesItsWordsDueDayAndBlockIdentifierWithoutTheTasksPluginsFields() throws {
        let task = try XCTUnwrap(MarkdownTaskLine(line: "  - [ ] Pay rent ⏫ 📅 2026-11-20 ➕ 2026-11-01 ^reminder-k3j9x2ab"))

        XCTAssertFalse(task.isDone)
        XCTAssertEqual(task.description, "Pay rent")
        XCTAssertEqual(task.dueDay, CalendarDay(year: 2026, month: 11, day: 20))
        XCTAssertEqual(task.blockIdentifier, "reminder-k3j9x2ab")

        let done = try XCTUnwrap(MarkdownTaskLine(line: "1. [x] Submit report ✅ 2026-11-12"))
        XCTAssertTrue(done.isDone)
        XCTAssertEqual(done.description, "Submit report")
        XCTAssertNil(done.dueDay)
        XCTAssertNil(done.blockIdentifier)
        XCTAssertEqual(MarkdownTaskLine(line: "* [ ] Call 📆 2026-11-13")?.dueDay, CalendarDay(year: 2026, month: 11, day: 13))
        for line in ["- Plain item", "Text [ ] not a task", "- [] Missing status", "- [ ]NoSpace"] {
            XCTAssertNil(MarkdownTaskLine(line: line), line)
        }
    }

    func testTheTaskAroundTheCursorAndTheTaskWithABlockIdentifierAreFoundInANote() throws {
        let text = "# Week\n\n- [ ] First 📅 2026-11-20\n- [ ] Second ^reminder-aaaa1111\nNot a task ^reminder-bbbb2222\n"
        let source = text as NSString

        let atCursor = try XCTUnwrap(MarkdownTaskLine.line(at: source.range(of: "First").location + 2, in: text))
        XCTAssertEqual(source.substring(with: atCursor.range), "- [ ] First 📅 2026-11-20")
        XCTAssertNil(MarkdownTaskLine.line(at: 2, in: text), "The heading is not a task.")
        let linked = try XCTUnwrap(MarkdownTaskLine.line(withBlockIdentifier: "reminder-aaaa1111", in: text))
        XCTAssertEqual(linked.task.description, "Second")
        XCTAssertNil(MarkdownTaskLine.line(withBlockIdentifier: "reminder-bbbb2222", in: text), "Only a task's block ID links it.")
        XCTAssertNil(MarkdownTaskLine.line(withBlockIdentifier: "reminder-aaaa", in: text), "A shorter ID is another ID.")
    }

    // MARK: Editing a task

    func testLinkingATaskAddsTheBlockIdentifierAtTheEndOnceAndKeepsAnExistingOne() throws {
        let text = "- [ ] Pay rent 📅 2026-11-20  \nNext\n"
        let range = try XCTUnwrap(MarkdownTaskLine.line(at: 0, in: text)).range

        let edit = try XCTUnwrap(TaskReminderEditing.linkingEdit(lineRange: range, in: text, blockIdentifier: "reminder-k3j9x2ab"))
        let linked = (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)

        XCTAssertEqual(linked, "- [ ] Pay rent 📅 2026-11-20 ^reminder-k3j9x2ab\nNext\n")
        let linkedRange = try XCTUnwrap(MarkdownTaskLine.line(at: 0, in: linked)).range
        XCTAssertNil(TaskReminderEditing.linkingEdit(lineRange: linkedRange, in: linked, blockIdentifier: "reminder-other"))
    }

    func testTickingATaskWritesTheDoneDayBeforeItsBlockIdentifierAndUntickingTakesItAway() throws {
        let text = "- [ ] Pay rent 📅 2026-11-20 ^reminder-k3j9x2ab"
        let range = NSRange(location: 0, length: (text as NSString).length)

        let tickEdit = try XCTUnwrap(TaskReminderEditing.completionEdit(lineRange: range, in: text, isDone: true, on: november12))
        let ticked = (text as NSString).replacingCharacters(in: tickEdit.range, with: tickEdit.replacement)
        XCTAssertEqual(ticked, "- [x] Pay rent 📅 2026-11-20 ✅ 2026-11-12 ^reminder-k3j9x2ab")
        XCTAssertNil(TaskReminderEditing.completionEdit(lineRange: NSRange(location: 0, length: (ticked as NSString).length), in: ticked, isDone: true, on: november12))

        let untickEdit = try XCTUnwrap(TaskReminderEditing.completionEdit(lineRange: NSRange(location: 0, length: (ticked as NSString).length), in: ticked,
                                                                           isDone: false, on: november12))
        XCTAssertEqual((ticked as NSString).replacingCharacters(in: untickEdit.range, with: untickEdit.replacement), text)

        let unlinked = "- [ ] Water plants   "
        let unlinkedEdit = try XCTUnwrap(TaskReminderEditing.completionEdit(lineRange: NSRange(location: 0, length: (unlinked as NSString).length), in: unlinked,
                                                                             isDone: true, on: november12))
        XCTAssertEqual(unlinkedEdit.replacement, "- [x] Water plants ✅ 2026-11-12")
    }

    func testNewBlockIdentifiersAreReminderAndEightLettersOrDigits() {
        var generator = SystemRandomNumberGenerator()
        let identifiers = (0..<50).map { _ in TaskReminderEditing.newBlockIdentifier(using: &generator) }

        for identifier in identifiers {
            XCTAssertNotNil(identifier.range(of: "^reminder-[a-z0-9]{8}$", options: .regularExpression), identifier)
            XCTAssertEqual(MarkdownTaskLine(line: "- [ ] Task ^" + identifier)?.blockIdentifier, identifier, "Obsidian reads it as a block ID.")
        }
        XCTAssertGreaterThan(Set(identifiers).count, 45)
    }

    // MARK: The reminder's link

    func testAReminderCarriesTheNotesOpeningLinkWithTheTasksBlockIdentifier() throws {
        let path = try VaultPath("Courses/Week 46.md")
        let opening = VaultURI.openingLink(to: path, inVaultNamed: "Study Vault")
        let link = try XCTUnwrap(ReminderTaskLink.url(openingLink: opening, blockIdentifier: "reminder-k3j9x2ab"))

        XCTAssertEqual(link.absoluteString, opening + "&block=reminder-k3j9x2ab")
        let target = try XCTUnwrap(ReminderTaskLink.target(of: link))
        XCTAssertEqual(target.vaultName, "Study Vault")
        XCTAssertEqual(target.notePath, path)
        XCTAssertEqual(target.blockIdentifier, "reminder-k3j9x2ab")
        XCTAssertNotNil(VaultURI(url: link), "The link still opens the note from Reminders.")
        XCTAssertNil(ReminderTaskLink.target(of: try XCTUnwrap(URL(string: opening))), "A link without a block ID is not a task's.")
        XCTAssertNil(ReminderTaskLink.target(of: try XCTUnwrap(URL(string: "https://example.com/?vault=A&file=B&block=C"))))
    }

    // MARK: Which side changed

    func testTheSideThatChangedSinceTheyLastAgreedWinsAndBeingDoneWinsWhenThatIsLost() {
        XCTAssertEqual(ReminderCompletionChange.needed(taskIsDone: true, reminderIsCompleted: true, lastAgreedCompletion: false), .none)
        XCTAssertEqual(ReminderCompletionChange.needed(taskIsDone: false, reminderIsCompleted: true, lastAgreedCompletion: false), .completeTask)
        XCTAssertEqual(ReminderCompletionChange.needed(taskIsDone: true, reminderIsCompleted: false, lastAgreedCompletion: true), .reopenTask)
        XCTAssertEqual(ReminderCompletionChange.needed(taskIsDone: true, reminderIsCompleted: false, lastAgreedCompletion: false), .completeReminder)
        XCTAssertEqual(ReminderCompletionChange.needed(taskIsDone: false, reminderIsCompleted: true, lastAgreedCompletion: true), .reopenReminder)
        XCTAssertEqual(ReminderCompletionChange.needed(taskIsDone: false, reminderIsCompleted: true, lastAgreedCompletion: nil), .completeTask)
        XCTAssertEqual(ReminderCompletionChange.needed(taskIsDone: true, reminderIsCompleted: false, lastAgreedCompletion: nil), .completeReminder)
    }

    // MARK: Reminders as tasks

    func testOpenRemindersBecomeTasksWithDueDaysGroupedByListOnlyWhenThereAreSeveral() {
        let milk = ReminderItem(id: "1", listTitle: "Groceries", title: "Milk", dueDay: CalendarDay(year: 2026, month: 11, day: 14))
        let bread = ReminderItem(id: "2", listTitle: "Groceries", title: "Bread")
        let eggs = ReminderItem(id: "3", listTitle: "Groceries", title: "Eggs", dueDay: CalendarDay(year: 2026, month: 11, day: 13))
        let done = ReminderItem(id: "4", listTitle: "Groceries", title: "Done", isCompleted: true)
        let report = ReminderItem(id: "5", listTitle: "Work", title: "Report\nfinal")

        XCTAssertEqual(ReminderTaskList.markdown(for: [milk, bread, eggs, done]), "- [ ] Eggs 📅 2026-11-13\n- [ ] Milk 📅 2026-11-14\n- [ ] Bread\n")
        XCTAssertEqual(ReminderTaskList.markdown(for: [report, milk]), "**Groceries**\n- [ ] Milk 📅 2026-11-14\n\n**Work**\n- [ ] Report final\n")
        XCTAssertEqual(ReminderTaskList.markdown(for: [done]), "")
        XCTAssertEqual(MarkdownTaskLine(line: "- [ ] Milk 📅 2026-11-14")?.dueDay, milk.dueDay, "A task brought in reads back with its due day.")
    }
}
