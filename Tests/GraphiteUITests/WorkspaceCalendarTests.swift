/**
 * File: WorkspaceCalendarTests.swift
 * ----------------------------------
 * Layer: Tests
 * Description: The Calendar core plugin in a workspace, over Calendar and Reminders that answer as each test sets
 *              them up: what is asked when, the days with daily notes, events in notes and templates, event notes,
 *              tasks sent to Reminders and ticked on either side, and reminders brought into a note.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

import XCTest
import GraphiteCore
import GraphiteApple
@testable import GraphiteUI
import GraphiteTestSupport

@MainActor
final class WorkspaceCalendarTests: XCTestCase {
    private var device: IsolatedWorkspaceDevice!
    private var calendarStore: FakeCalendarStore { device.calendarStore }
    private var calendar: Calendar { .autoupdatingCurrent }
    private let november12 = CalendarDay(year: 2026, month: 11, day: 12)

    override func setUp() async throws {
        device = try IsolatedWorkspaceDevice.make(for: self)
    }

    private func openedWorkspace(files: [String: String]) async throws -> (WorkspaceModel, URL) {
        let vault = try TemporaryVault.make(prefix: "CalendarVault", files: files, for: self).root
        let workspace = device.makeWorkspace()
        try await workspace.openFolderAsVault(vault)
        return (workspace, vault)
    }

    private func date(_ day: CalendarDay, hour: Int, minute: Int = 0) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: hour, minute: minute)))
    }

    private func lecture() throws -> CalendarEvent {
        CalendarEvent(id: "lecture", calendarTitle: "Courses", title: "Computer Architecture", startDate: try date(november12, hour: 10, minute: 15),
                      endDate: try date(november12, hour: 12), location: "ETZ E 6", attendees: ["Prof. Mutlu"])
    }

    private func text(of rawPath: String, in vault: URL) throws -> String {
        try String(contentsOf: vault.appendingPathComponent(rawPath), encoding: .utf8)
    }

    private func openedNote(_ rawPath: String, in workspace: WorkspaceModel) async throws -> MarkdownSession {
        await workspace.open(try VaultPath(rawPath))
        return try XCTUnwrap(workspace.markdownSession)
    }

    // MARK: Nothing is asked before a feature is used

    func testOpeningAVaultListingCommandsAndComingToTheFrontAskNothingOfCalendarOrReminders() async throws {
        let (workspace, _) = try await openedWorkspace(files: ["Note.md": "- [ ] Task 📅 2026-11-20 ^reminder-aaaa1111\n"])
        await workspace.open(try VaultPath("Note.md"))

        _ = WorkspaceCommandList.commands(for: workspace, window: WindowActions(showQuickSwitcher: {}, showSettings: {}, showVaultManager: {},
                                                                                toggleLinksInspector: {}, toggleSidebar: {}, showSidebar: {},
                                                                                showLinksInspector: {}, create: { _ in }, showTemplatePicker: {},
                                                                                showTabOverview: {}))
        await workspace.updateLinkedTasksAndReminders()

        XCTAssertFalse(calendarStore.wasAskedAnything, "Nothing reads even the access before the person uses a calendar or reminders feature.")
        XCTAssertEqual(calendarStore.listenerCount, 0)
    }

    func testChangesAreListenedToOnlyWhileSomethingFollowsThem() {
        let services = CalendarServices(store: calendarStore)
        let follower = NSObject()
        XCTAssertFalse(services.isListening)

        services.follow(follower) {}
        XCTAssertTrue(services.isListening)
        services.stopFollowing(follower)

        XCTAssertFalse(services.isListening)
        XCTAssertEqual(calendarStore.accessRequestCount + calendarStore.readCount, 0, "Listening asks nothing and reads nothing.")
    }

    // MARK: The month view

    func testTheDaysWithADailyNoteInTheDailyNotesFolderAreMarked() async throws {
        let (workspace, _) = try await openedWorkspace(files: [
            ".obsidian/daily-notes.json": #"{"folder": "Daily"}"#, "Daily/2026-11-10.md": "x\n", "Daily/2026-11-12.md": "x\n",
            "Daily/Shopping.md": "x\n", "2026-11-11.md": "Outside the folder\n",
        ])
        let index = try XCTUnwrap(workspace.index)
        try await waitUntil("the daily notes are indexed") { try await index.paths(inside: .root).count == 4 }

        let days = await workspace.dailyNoteDays()

        XCTAssertEqual(days, [CalendarDay(year: 2026, month: 11, day: 10), november12])
        XCTAssertFalse(calendarStore.wasAskedAnything, "The marks need no calendar access.")
    }

    func testChoosingADayOpensItsDailyNoteMadeFromTheTemplateWithTheDaysEventsOnceAccessIsAllowed() async throws {
        let (workspace, vault) = try await openedWorkspace(files: [
            ".obsidian/daily-notes.json": #"{"folder": "Daily", "template": "Templates/Day"}"#,
            "Templates/Day.md": "# {{date:dddd}}\n\n## Agenda\n{{events}}\n## Notes\n",
        ])
        calendarStore.events = [try lecture()]
        let model = CalendarPanelModel(today: november12.adding(days: -3, in: calendar))

        await model.choose(november12, actions: workspace.calendarPanelActions())

        XCTAssertEqual(workspace.selection?.rawValue, "Daily/2026-11-12.md")
        XCTAssertEqual(try text(of: "Daily/2026-11-12.md", in: vault),
                       "# Thursday\n\n## Agenda\n- **10:15–12:00** Computer Architecture (ETZ E 6)\n## Notes\n")
        XCTAssertEqual(calendarStore.accessRequestCount, 1, "The template's {{events}} is a use of the calendar, which asks.")
        XCTAssertEqual(model.selectedDay, november12)
        XCTAssertEqual(model.events, .loaded([try lecture()]))
    }

    func testWithoutCalendarAccessTheDailyNoteIsStillMadeAndThePanelSaysWhereToAllowIt() async throws {
        let (workspace, vault) = try await openedWorkspace(files: [
            ".obsidian/daily-notes.json": #"{"template": "Day"}"#, "Day.md": "{{events}}\nText\n",
        ])
        calendarStore.answers = [.events: .refused, .reminders: .refused]
        let model = CalendarPanelModel(today: november12)

        await model.choose(november12, actions: workspace.calendarPanelActions())

        XCTAssertEqual(try text(of: "2026-11-12.md", in: vault), "\nText\n")
        XCTAssertEqual(model.events, .unavailable(.refused))
        XCTAssertNotNil(workspace.notice, "The person is told why the events are missing.")
        await model.choose(november12.adding(days: 1, in: calendar), actions: workspace.calendarPanelActions())
        XCTAssertEqual(calendarStore.accessRequestCount, 1, "The question is not asked again.")
    }

    func testThePanelShowsEventsOnlyAfterThePersonChoosesToAndAsksOnce() async throws {
        let (workspace, _) = try await openedWorkspace(files: [:])
        calendarStore.events = [try lecture()]
        let model = CalendarPanelModel(today: november12)
        var actions = workspace.calendarPanelActions()
        actions = CalendarPanelActions(dailyNoteDays: actions.dailyNoteDays, eventAccess: actions.eventAccess, events: actions.events,
                                       openDailyNote: actions.openDailyNote, openEventNote: actions.openEventNote, opensDailyNotes: false)

        await model.loadEvents(actions: actions)
        XCTAssertEqual(model.events, .notAsked)
        XCTAssertEqual(calendarStore.accessRequestCount, 0, "Showing the panel never asks.")

        await model.allowEvents(actions: actions)
        XCTAssertEqual(model.events, .loaded([try lecture()]))
        await model.choose(november12.adding(days: 1, in: calendar), actions: actions)
        XCTAssertEqual(model.events, .loaded([]))
        XCTAssertNil(workspace.selection, "With Daily notes off, choosing a day opens nothing.")
        XCTAssertEqual(calendarStore.accessRequestCount, 1)
    }

    // MARK: Events in a note

    func testInsertingTheDaysEventsWritesTheDailyNotesOwnDayAtTheCursorWithALinkToAnEventsNote() async throws {
        let (workspace, _) = try await openedWorkspace(files: [
            "2026-11-12.md": "# Today\n", "2026-11-12 Computer Architecture.md": "Notes\n",
        ])
        calendarStore.events = [try lecture()]
        let session = try await openedNote("2026-11-12.md", in: workspace)
        session.selection = NSRange(location: (session.text as NSString).length, length: 0)

        await workspace.insertCalendarEvents(into: session)

        XCTAssertEqual(session.text, "# Today\n- **10:15–12:00** Computer Architecture (ETZ E 6) [[2026-11-12 Computer Architecture]]\n")
        XCTAssertNil(workspace.errorMessage)
    }

    func testInsertingEventsWithoutAccessChangesNothingAndSaysWhereToAllowIt() async throws {
        let (workspace, _) = try await openedWorkspace(files: ["Note.md": "Text\n"])
        calendarStore.answers = [.events: .refused, .reminders: .refused]
        let session = try await openedNote("Note.md", in: workspace)

        await workspace.insertCalendarEvents(into: session)

        XCTAssertEqual(session.text, "Text\n")
        XCTAssertEqual(workspace.errorMessage, CalendarStoreError.accessRefused(.events).errorDescription)
    }

    func testWithTheCalendarPluginOffATemplatesEventsVariableStaysAsWritten() async throws {
        let (workspace, vault) = try await openedWorkspace(files: [".obsidian/daily-notes.json": #"{"template": "Day"}"#, "Day.md": "{{events}}\n"])
        workspace.setCorePluginEnabled(.calendar, false)

        await workspace.openDailyNote(on: november12)

        XCTAssertEqual(try text(of: "2026-11-12.md", in: vault), "{{events}}\n")
        XCTAssertFalse(calendarStore.wasAskedAnything)
    }

    // MARK: Event notes

    func testAnEventsNoteIsMadeOnceInItsCalendarsFolderWithTheEventAsProperties() async throws {
        let (workspace, vault) = try await openedWorkspace(files: [".obsidian/graphite-calendar.json": #"{"eventNoteFolders": {"Courses": "Lectures"}}"#])

        await workspace.openNote(for: try lecture())
        try Data("Edited\n".utf8).write(to: vault.appendingPathComponent("Lectures/2026-11-12 Computer Architecture.md"))
        await workspace.openNote(for: try lecture())

        XCTAssertEqual(workspace.selection?.rawValue, "Lectures/2026-11-12 Computer Architecture.md")
        XCTAssertEqual(try text(of: "Lectures/2026-11-12 Computer Architecture.md", in: vault), "Edited\n", "An existing note opens as it is.")
    }

    func testANoteForTheCurrentEventIsTheOneUnderWayOrElseTheNextOne() async throws {
        let (workspace, vault) = try await openedWorkspace(files: [:])
        let standup = CalendarEvent(id: "standup", calendarTitle: "Work", title: "Standup", startDate: try date(november12, hour: 9), endDate: try date(november12, hour: 9, minute: 15))
        calendarStore.events = [standup, try lecture()]

        await workspace.openNoteForCurrentEvent(at: try date(november12, hour: 9, minute: 5))
        XCTAssertEqual(workspace.selection?.rawValue, "2026-11-12 Standup.md")
        await workspace.openNoteForCurrentEvent(at: try date(november12, hour: 9, minute: 30))
        XCTAssertEqual(workspace.selection?.rawValue, "2026-11-12 Computer Architecture.md")
        XCTAssertTrue(try text(of: "2026-11-12 Computer Architecture.md", in: vault).hasPrefix("---\ndate: 2026-11-12\nstart: 2026-11-12T10:15\n"))
        await workspace.openNoteForCurrentEvent(at: try date(november12, hour: 13))
        XCTAssertEqual(workspace.notice, "No event is under way or still to come today.")
    }

    // MARK: Tasks and Reminders

    func testSendingATaskAddsItsReminderAndLinksTheTaskByABlockIdentifier() async throws {
        let (workspace, _) = try await openedWorkspace(files: [".obsidian/graphite-calendar.json": #"{"taskList": "Inbox"}"#,
                                                               "Week.md": "# Week\n- [ ] Pay rent ⏫ 📅 2026-11-20\n"])
        let session = try await openedNote("Week.md", in: workspace)
        session.selection = NSRange(location: (session.text as NSString).range(of: "rent").location, length: 0)

        await workspace.sendTaskToReminders(from: session)

        let reminder = try XCTUnwrap(calendarStore.storedReminders.first)
        XCTAssertEqual(reminder.title, "Pay rent")
        XCTAssertEqual(reminder.dueDay, CalendarDay(year: 2026, month: 11, day: 20))
        XCTAssertEqual(reminder.listTitle, "Inbox")
        let target = try XCTUnwrap(reminder.link.flatMap(ReminderTaskLink.target(of:)))
        XCTAssertEqual(target.notePath.rawValue, "Week.md")
        XCTAssertEqual(session.text, "# Week\n- [ ] Pay rent ⏫ 📅 2026-11-20 ^\(target.blockIdentifier)\n")
        XCTAssertEqual(calendarStore.listenerCount, 1, "Reminders' changes are followed once a task is linked.")

        await workspace.sendTaskToReminders(from: session)
        XCTAssertEqual(calendarStore.storedReminders.count, 1, "A task is sent once.")
        XCTAssertEqual(workspace.notice, "This task is in Reminders already.")
    }

    func testATaskCompletedInRemindersIsTickedInTheNoteAndATaskTickedInTheNoteCompletesItsReminder() async throws {
        let (workspace, vault) = try await openedWorkspace(files: ["Week.md": "- [ ] Pay rent\n- [ ] Call home\n"])
        let session = try await openedNote("Week.md", in: workspace)
        await workspace.sendTaskToReminders(from: session)
        session.selection = NSRange(location: (session.text as NSString).range(of: "Call").location, length: 0)
        await workspace.sendTaskToReminders(from: session)
        try await session.save()
        let rentReminder = try XCTUnwrap(calendarStore.storedReminders.first { reminder in reminder.title == "Pay rent" })

        calendarStore.completeInReminders(rentReminder.id)
        try await waitUntil("the task is ticked in its note") { session.text.hasPrefix("- [x] Pay rent ✅ ") }
        XCTAssertTrue(try text(of: "Week.md", in: vault).hasPrefix("- [x] Pay rent ✅ "), "A note without an editor is saved at once.")

        let callLine = try XCTUnwrap(MarkdownTaskLine.line(at: (session.text as NSString).range(of: "Call").location, in: session.text))
        session.apply(try XCTUnwrap(TaskReminderEditing.completionEdit(lineRange: callLine.range, in: session.text, isDone: true, on: november12)))
        await workspace.updateLinkedTasksAndReminders()
        XCTAssertEqual(calendarStore.storedReminders.first { reminder in reminder.title == "Call home" }?.isCompleted, true)

        calendarStore.completeInReminders(rentReminder.id, isCompleted: false)
        try await waitUntil("the task is unticked again") { session.text.hasPrefix("- [ ] Pay rent ^reminder-") }
        XCTAssertFalse(calendarStore.savedChanges.contains { change in
            if case .setCompleted(let identifier, _) = change { return identifier == rentReminder.id }
            return false
        }, "A change made in Reminders is never written back to Reminders.")
    }

    func testSendingAskForRemindersAccessOnceAndWithoutItNothingChanges() async throws {
        let (workspace, _) = try await openedWorkspace(files: ["Week.md": "- [ ] Pay rent\n"])
        calendarStore.answers = [.events: .refused, .reminders: .refused]
        let session = try await openedNote("Week.md", in: workspace)

        await workspace.sendTaskToReminders(from: session)
        await workspace.sendTaskToReminders(from: session)

        XCTAssertEqual(session.text, "- [ ] Pay rent\n")
        XCTAssertEqual(calendarStore.accessRequestCount, 1)
        XCTAssertEqual(workspace.errorMessage, CalendarStoreError.accessRefused(.reminders).errorDescription)
        XCTAssertNil(device.defaults.object(forKey: WorkspaceModel.usesRemindersKey))
    }

    func testOpenRemindersOfTheChosenListAreInsertedAsTasks() async throws {
        let (workspace, _) = try await openedWorkspace(files: [".obsidian/graphite-calendar.json": #"{"importedList": "Groceries"}"#, "List.md": ""])
        calendarStore.setAccess(.granted, for: .reminders)
        try await calendarStore.save(.add(ReminderDraft(title: "Milk", dueDay: CalendarDay(year: 2026, month: 11, day: 14), listTitle: "Inbox",
                                                        link: try XCTUnwrap(URL(string: "https://example.com")))))
        calendarStore.reminderLists.append(CalendarList(id: "groceries", title: "Groceries"))
        try await calendarStore.save(.add(ReminderDraft(title: "Bread", dueDay: nil, listTitle: "Groceries", link: try XCTUnwrap(URL(string: "https://example.com")))))
        let session = try await openedNote("List.md", in: workspace)

        await workspace.insertReminders(into: session)

        XCTAssertEqual(session.text, "- [ ] Bread\n")
    }

    func testForgettingAVaultForgetsItsLinkedTasks() async throws {
        let (workspace, _) = try await openedWorkspace(files: ["Week.md": "- [ ] Pay rent\n"])
        let session = try await openedNote("Week.md", in: workspace)
        await workspace.sendTaskToReminders(from: session)
        let firstVault = try XCTUnwrap(workspace.currentVaultIdentifier)
        XCTAssertNotNil(device.defaults.dictionary(forKey: WorkspaceModel.linkedTasksKey(for: firstVault)))
        try await session.save()

        let otherVault = try TemporaryVault.make(prefix: "OtherCalendarVault", files: ["Other.md": "x\n"], for: self).root
        try await workspace.openFolderAsVault(otherVault)
        try workspace.removeFromVaultList(try XCTUnwrap(workspace.vaultLibrary.vault(withIdentifier: firstVault)))

        XCTAssertNil(device.defaults.object(forKey: WorkspaceModel.linkedTasksKey(for: firstVault)))
    }
}
