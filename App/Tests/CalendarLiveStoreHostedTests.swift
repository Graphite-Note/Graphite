/**
 * File: CalendarLiveStoreHostedTests.swift
 * ----------------------------------------
 * Layer: Tests
 * Description: The Calendar core plugin over the simulator's real Calendar and Reminders (EventKit): a repeating
 *              lecture, an event made in another time zone and an all-day event listed in a note, an event's note,
 *              a task sent to a Reminders list and completed there, and open reminders brought into a note.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

#if os(iOS)
import XCTest
import EventKit
import GraphiteCore
@testable import GraphiteApple
@testable import GraphiteUI

/// Docs/Calendar-and-reminders-todo.md: the checks "with real calendars". Runs only with
/// `TEST_RUNNER_GRAPHITE_LIVE_CALENDAR=1` given to xcodebuild, in a simulator of the session's own where access was
/// given beforehand (`xcrun simctl privacy <device> grant calendar com.graphite.study`, and `reminders`): it writes a
/// calendar and a Reminders list of its own there and removes them afterwards. Never on a person's device.
@MainActor
final class CalendarLiveStoreHostedTests: XCTestCase {
    static let switchVariable = "GRAPHITE_LIVE_CALENDAR"
    private let eventStore = EKEventStore()
    private let calendar = Calendar.autoupdatingCurrent
    private let march10 = CalendarDay(year: 2031, month: 3, day: 10)

    func testRealEventsAndRemindersReachNotesAndComeBack() async throws {
        // Returns rather than skipping: the suites' skip count may not rise (FR-93), and this is not a missing capability.
        guard ProcessInfo.processInfo.environment[Self.switchVariable] == "1" else { return }
        XCTAssertEqual(LiveCalendarStore().access(to: .events), .granted, "Grant the simulator calendar access first.")
        XCTAssertEqual(LiveCalendarStore().access(to: .reminders), .granted, "Grant the simulator reminders access first.")
        let courses = try makeList(titled: "Graphite Test Courses", for: .event)
        let inbox = try makeList(titled: "Graphite Test Inbox", for: .reminder)
        addTeardownBlock { @MainActor in
            try? self.eventStore.removeCalendar(courses, commit: true)
            try? self.eventStore.removeCalendar(inbox, commit: true)
        }
        try addEvents(to: courses)
        let (workspace, vault) = try await openedWorkspace()

        // The day's events, as the command inserts them: the all-day event first, an occurrence of the repeating
        // lecture, the New York call at the device's own time.
        let list = try await workspace.calendarEventList(on: march10, linkingFrom: nil)
        print("GRAPHITE-LIVE-CALENDAR list:\n\(list)")
        let lines = list.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.first, "- **All day** Exam week")
        XCTAssertTrue(lines.contains("- **10:15–12:00** VLSI 3 (ETZ E 6)"), list)
        let callStart = try localTime(hour: 9, in: "America/New_York")
        let callEnd = try localTime(hour: 10, in: "America/New_York")
        XCTAssertTrue(lines.contains("- **\(callStart)–\(callEnd)** Call with Boston"), list)
        XCTAssertEqual(lines.count, 3, list)
        let march17 = CalendarDay(year: 2031, month: 3, day: 17)
        var nextWeek = ""
        for _ in 0..<40 where nextWeek.isEmpty {
            nextWeek = try await workspace.calendarEventList(on: march17, linkingFrom: nil)
            if nextWeek.isEmpty { await pause() }
        }
        let rawMarch17 = eventStore.events(matching: eventStore.predicateForEvents(withStart: try XCTUnwrap(march17.startDate(in: calendar)),
                                                                                    end: try XCTUnwrap(march17.adding(days: 1, in: calendar).startDate(in: calendar)),
                                                                                    calendars: [courses])).map { event in "\(event.title ?? "") \(event.startDate!)" }
        print("GRAPHITE-LIVE-CALENDAR next week: \(nextWeek.isEmpty ? "nothing" : nextWeek); EventKit itself: \(rawMarch17)")
        XCTAssertEqual(nextWeek.trimmingCharacters(in: .newlines), "- **10:15–12:00** VLSI 3 (ETZ E 6)", "The lecture repeats each week.")

        // The lecture's note, from a real occurrence.
        let marchTenthEvents = try await workspace.calendarEvents(on: march10)
        let lecture = try XCTUnwrap(marchTenthEvents.first { event in event.title == "VLSI 3" })
        await workspace.openNote(for: lecture)
        let notePath = "Lectures/2031-03-10 VLSI 3.md"
        XCTAssertEqual(workspace.selection?.rawValue, notePath)
        let noteText = try String(contentsOf: vault.appendingPathComponent(notePath), encoding: .utf8)
        print("GRAPHITE-LIVE-CALENDAR note:\n\(noteText)")
        XCTAssertTrue(noteText.hasPrefix("---\ndate: 2031-03-10\nstart: 2031-03-10T10:15\nend: 2031-03-10T12:00\nlocation: ETZ E 6\n"), noteText)
        XCTAssertTrue(noteText.contains("calendar: Graphite Test Courses"), noteText)

        // A task sent to the Reminders list, completed in Reminders, ticked in its note.
        _ = await workspace.open(try VaultPath("Week.md"))
        let session = try XCTUnwrap(workspace.markdownSession)
        await workspace.sendTaskToReminders(from: session)
        XCTAssertNil(workspace.errorMessage)
        try await session.save()
        let sentReminders = try await reminders(in: inbox)
        let reminder = try XCTUnwrap(sentReminders.first { reminder in reminder.title == "Pay rent" })
        XCTAssertEqual(reminder.dueDateComponents?.year, 2031)
        XCTAssertEqual(reminder.dueDateComponents?.month, 3)
        XCTAssertEqual(reminder.dueDateComponents?.day, 12)
        XCTAssertEqual(reminder.url?.scheme, "graphite")
        reminder.isCompleted = true
        try eventStore.save(reminder, commit: true)
        await workspace.updateLinkedTasksAndReminders()
        try await waitUntil("the task is ticked in its note", timeoutSeconds: 20) { session.text.hasPrefix("- [x] Pay rent 📅 2031-03-12") }
        XCTAssertTrue(session.text.contains(" ✅ "), session.text)

        // Unticked in the note, the reminder is open again.
        let taskLine = try XCTUnwrap(MarkdownTaskLine.line(at: 0, in: session.text))
        session.apply(try XCTUnwrap(TaskReminderEditing.completionEdit(lineRange: taskLine.range, in: session.text, isDone: false, on: march10)))
        try await session.save()
        await workspace.updateLinkedTasksAndReminders()
        XCTAssertNil(workspace.errorMessage)
        let graphitesView = try await workspace.processServices.calendar.store.reminders().filter { reminder in reminder.title == "Pay rent" }
        print("GRAPHITE-LIVE-CALENDAR untick: note on disk \(try String(contentsOf: vault.appendingPathComponent("Week.md"), encoding: .utf8).debugDescription), "
              + "session \(session.text.debugDescription), Graphite's store: \(graphitesView.map { reminder in "\(reminder.title) completed \(reminder.isCompleted)" })")
        var reopened = false
        for _ in 0..<40 where !reopened {
            // Graphite saved through its own event store; this test's store hears of it a moment later.
            reopened = try await reminders(in: inbox).first { reminder in reminder.title == "Pay rent" }?.isCompleted == false
            if !reopened { await pause() }
        }
        XCTAssertTrue(reopened, "Unticking the task reopened its reminder.")

        // The list's open reminders inserted as tasks.
        let milk = EKReminder(eventStore: eventStore)
        milk.title = "Buy milk"
        milk.calendar = try XCTUnwrap(eventStore.calendar(withIdentifier: inbox.calendarIdentifier))
        milk.dueDateComponents = DateComponents(year: 2031, month: 3, day: 14)
        try eventStore.save(milk, commit: true)
        _ = await workspace.open(try VaultPath("Shopping.md"))
        let shopping = try XCTUnwrap(workspace.markdownSession)
        await workspace.insertReminders(into: shopping)
        print("GRAPHITE-LIVE-CALENDAR reminders:\n\(shopping.text)")
        XCTAssertTrue(shopping.text.contains("- [ ] Buy milk 📅 2031-03-14"), shopping.text)
    }

    // MARK: The simulator's calendars

    private func makeList(titled title: String, for entityType: EKEntityType) throws -> EKCalendar {
        for existing in eventStore.calendars(for: entityType) where existing.title == title { try eventStore.removeCalendar(existing, commit: true) }
        let list = EKCalendar(for: entityType, eventStore: eventStore)
        list.title = title
        let defaultSource = entityType == .event ? eventStore.defaultCalendarForNewEvents?.source : eventStore.defaultCalendarForNewReminders()?.source
        list.source = try XCTUnwrap(defaultSource ?? eventStore.sources.first { source in source.sourceType == .local })
        try eventStore.saveCalendar(list, commit: true)
        return list
    }

    private func addEvents(to courses: EKCalendar) throws {
        let zurich = try XCTUnwrap(TimeZone(identifier: "Europe/Zurich"))
        let lecture = EKEvent(eventStore: eventStore)
        lecture.calendar = courses
        lecture.title = "VLSI 3"
        lecture.location = "ETZ E 6"
        lecture.timeZone = zurich
        lecture.startDate = try date(year: 2031, month: 3, day: 3, hour: 10, minute: 15, in: zurich)
        lecture.endDate = try date(year: 2031, month: 3, day: 3, hour: 12, minute: 0, in: zurich)
        lecture.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: EKRecurrenceEnd(occurrenceCount: 4)))
        try eventStore.save(lecture, span: .futureEvents, commit: false)

        let newYork = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let call = EKEvent(eventStore: eventStore)
        call.calendar = courses
        call.title = "Call with Boston"
        call.timeZone = newYork
        call.startDate = try date(year: 2031, month: 3, day: 10, hour: 9, minute: 0, in: newYork)
        call.endDate = try date(year: 2031, month: 3, day: 10, hour: 10, minute: 0, in: newYork)
        try eventStore.save(call, span: .thisEvent, commit: false)

        let exams = EKEvent(eventStore: eventStore)
        exams.calendar = courses
        exams.title = "Exam week"
        exams.isAllDay = true
        exams.startDate = try XCTUnwrap(march10.startDate(in: calendar))
        exams.endDate = exams.startDate
        try eventStore.save(exams, span: .thisEvent, commit: false)
        try eventStore.commit()
    }

    /// A quarter of a second in which the run loop goes on, for a change made through another event store to arrive.
    private func pause() async {
        _ = await XCTWaiter.fulfillment(of: [XCTestExpectation(description: "a quarter of a second")], timeout: 0.25)
    }

    private func reminders(in list: EKCalendar) async throws -> [EKReminder] {
        eventStore.reset()
        let current = try XCTUnwrap(eventStore.calendar(withIdentifier: list.calendarIdentifier))
        let predicate = eventStore.predicateForReminders(in: [current])
        let identifiers: [String] = await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { @Sendable reminders in
                continuation.resume(returning: (reminders ?? []).map(\.calendarItemIdentifier))
            }
        }
        return identifiers.compactMap { identifier in eventStore.calendarItem(withIdentifier: identifier) as? EKReminder }
    }

    private func date(year: Int, month: Int, day: Int, hour: Int, minute: Int, in timeZone: TimeZone) throws -> Date {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = timeZone
        return try XCTUnwrap(gregorian.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)))
    }

    /// The device's clock time of `hour` o'clock on March 10 in `zoneIdentifier`, as the list writes it.
    private func localTime(hour: Int, in zoneIdentifier: String) throws -> String {
        let moment = try date(year: 2031, month: 3, day: 10, hour: hour, minute: 0, in: try XCTUnwrap(TimeZone(identifier: zoneIdentifier)))
        let components = calendar.dateComponents([.hour, .minute], from: moment)
        return String(format: "%02ld:%02ld", components.hour ?? 0, components.minute ?? 0)
    }

    // MARK: The workspace

    private func openedWorkspace() async throws -> (WorkspaceModel, URL) {
        let vault = try TemporaryVault.make(prefix: "LiveCalendarVault", files: [
            ".obsidian/graphite-calendar.json": #"{"eventNoteFolders": {"Graphite Test Courses": "Lectures"}, "taskList": "Graphite Test Inbox", "importedList": "Graphite Test Inbox"}"#,
            "Week.md": "- [ ] Pay rent 📅 2031-03-12\n",
            "Shopping.md": "",
        ], for: self).root
        let suiteName = "LiveCalendar-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let folders = try TemporaryVault.make(prefix: "LiveCalendarFolders", for: self).root
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suiteName) }
        let services = ProcessServices(defaults: defaults, applicationFolders: .temporary(below: folders), calendarStore: LiveCalendarStore()) { startRefusal in
            ReadAloudController(session: ReadAloudSession(speech: PenTestSpeech(), preferences: defaults), preferences: defaults, startRefusal: startRefusal)
        }
        let workspace = WorkspaceModel(processServices: services, clock: LiveApplicationClock())
        try await workspace.openFolderAsVault(vault)
        return (workspace, vault)
    }
}
#endif
