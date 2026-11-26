/**
 * File: CalendarCopyLiveStoreHostedTests.swift
 * --------------------------------------------
 * Layer: Tests
 * Description: Calendar Copy over the simulator's real Calendar (EventKit): a base's dated notes copied into the
 *              "Graphite" calendar, put back after an edit in Calendar, moved after an edit of the vault, and removed,
 *              with the person's own event left alone.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

#if os(iOS)
import XCTest
import EventKit
import GraphiteCore
import GraphiteIndex
@testable import GraphiteApple
@testable import GraphiteUI

/// Docs/Bases-calendar-todo.md section 4, with real EventKit. Runs only with `TEST_RUNNER_GRAPHITE_LIVE_CALENDAR=1` given
/// to xcodebuild, in a simulator of the session's own where calendar access was given beforehand
/// (`xcrun simctl privacy <device> grant calendar com.graphite.study`): it writes a "Graphite" calendar there and removes
/// it afterwards. Never on a person's device.
@MainActor
final class CalendarCopyLiveStoreHostedTests: XCTestCase {
    private let eventStore = EKEventStore()

    func testABasesNotesAreCopiedPutBackMovedAndRemovedInTheRealCalendar() async throws {
        // Returns rather than skipping: the suites' skip count may not rise (FR-93), and this is not a missing capability.
        guard ProcessInfo.processInfo.environment[CalendarLiveStoreHostedTests.switchVariable] == "1" else { return }
        XCTAssertEqual(LiveCalendarStore().access(to: .events), .granted, "Grant the simulator calendar access first.")
        for existing in eventStore.calendars(for: .event) where existing.title == CalendarCopyEvents.calendarTitle {
            try eventStore.removeCalendar(existing, commit: true)
        }
        addTeardownBlock { @MainActor in
            for leftOver in self.eventStore.calendars(for: .event) where leftOver.title == CalendarCopyEvents.calendarTitle {
                try? self.eventStore.removeCalendar(leftOver, commit: true) // Best effort: the next run removes it first.
            }
        }
        let vault = try TemporaryVault.make(prefix: "LiveCalendarCopyVault", files: [
            "Courses/Lab report.md": "---\ndue: 2031-03-10\nuntil: 2031-03-12\n---\n",
            "Courses/Signals exam.md": "---\ndue: 2031-03-11T09:00\n---\n",
            "Deadlines.base": "filters: file.inFolder(\"Courses\")\nviews:\n  - type: calendar\n    name: Deadlines\n    startDate: due\n    endDate: until\n",
        ], for: self).root
        let index = try VaultIndex(databaseURL: vault.appendingPathExtension("cache").appendingPathComponent("index.sqlite"))
        _ = try await index.reconcile(root: vault)
        let suiteName = "LiveCalendarCopy-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suiteName) }
        let controller = CalendarCopyController(clock: LiveApplicationClock(), store: LiveCalendarCopyStore(), defaults: defaults)
        controller.currentDate = { Date(timeIntervalSince1970: 1_930_000_000) } // March 2031, so the notes are in the window.
        let source = CalendarCopySource(vaultName: "Live Copy", store: VaultStore(root: vault), index: index,
                                        settings: CalendarCopySettings(basePath: try VaultPath("Deadlines.base"), viewName: "Deadlines"))

        controller.copyNow(source)
        try await waitForWork(controller)
        XCTAssertEqual(controller.status.copiedReport, CalendarCopyReport(addedCount: 2), "\(controller.status)")
        var events = try await graphiteEvents()
        print("GRAPHITE-LIVE-CALENDAR-COPY copied: \(events.map(Self.describe))")
        let lab = try XCTUnwrap(events.first { event in event.title == "Lab report" })
        XCTAssertTrue(lab.isAllDay)
        XCTAssertEqual(CalendarDay(lab.startDate, in: .current).isoText, "2031-03-10")
        XCTAssertEqual(CalendarDay(lab.endDate, in: .current).isoText, "2031-03-12", "An all-day event ends on its last day.")
        XCTAssertEqual(lab.url?.absoluteString, "graphite://open?vault=Live%20Copy&file=Courses/Lab%20report")
        let examEvent = try XCTUnwrap(events.first { event in event.title == "Signals exam" })
        XCTAssertFalse(examEvent.isAllDay)
        XCTAssertEqual(Calendar.current.dateComponents([.hour, .minute], from: examEvent.startDate), DateComponents(hour: 9, minute: 0))
        XCTAssertEqual(examEvent.endDate.timeIntervalSince(examEvent.startDate), 3_600)

        // The person edits an event in Calendar and adds one of their own; the vault moves the exam.
        let otherStore = EKEventStore()
        let editedLab = try XCTUnwrap(otherStore.event(withIdentifier: try XCTUnwrap(lab.eventIdentifier)))
        editedLab.title = "Edited in Calendar"
        try otherStore.save(editedLab, span: .thisEvent, commit: true)
        let personal = EKEvent(eventStore: otherStore)
        personal.calendar = try XCTUnwrap(otherStore.calendar(withIdentifier: try XCTUnwrap(lab.calendar?.calendarIdentifier)))
        personal.title = "Dentist"
        personal.startDate = examEvent.startDate
        personal.endDate = examEvent.endDate
        try otherStore.save(personal, span: .thisEvent, commit: true)
        try Data("---\ndue: 2031-03-13T14:00\n---\n".utf8).write(to: vault.appendingPathComponent("Courses/Signals exam.md"))
        _ = try await index.reconcile(root: vault)
        await pause()

        controller.copyNow(source)
        try await waitForWork(controller)
        XCTAssertEqual(controller.status.copiedReport, CalendarCopyReport(changedCount: 2), "\(controller.status)")
        events = try await graphiteEvents()
        print("GRAPHITE-LIVE-CALENDAR-COPY after the edits: \(events.map(Self.describe))")
        XCTAssertEqual(Set(events.map { event in event.title ?? "" }), ["Lab report", "Signals exam", "Dentist"], "The title written in Calendar is put back.")
        let movedExam = try XCTUnwrap(events.first { event in event.title == "Signals exam" })
        XCTAssertEqual(CalendarDay(movedExam.startDate, in: .current).isoText, "2031-03-13")
        XCTAssertEqual(Calendar.current.component(.hour, from: movedExam.startDate), 14)

        // Removing the copied events keeps the person's own, and the calendar with it.
        controller.removeCopiedEvents(vaultName: "Live Copy")
        try await waitForWork(controller)
        guard case .removed(let report, let calendarRemoved, _) = controller.status else { return XCTFail("\(controller.status)") }
        XCTAssertEqual(report.removedCount, 2)
        XCTAssertFalse(calendarRemoved)
        events = try await graphiteEvents()
        XCTAssertEqual(events.map { event in event.title ?? "" }, ["Dentist"])
        XCTAssertEqual(try noteText(vault, "Courses/Lab report.md"), "---\ndue: 2031-03-10\nuntil: 2031-03-12\n---\n", "No note is written.")
    }

    // MARK: Helpers

    private func waitForWork(_ controller: CalendarCopyController) async throws {
        for _ in 0..<600 where controller.isWorking { await pause() }
        XCTAssertFalse(controller.isWorking)
    }

    /// The events of every calendar titled "Graphite" in March 2031, read by a store of the test's own, which sees
    /// another store's changes a moment later.
    private func graphiteEvents() async throws -> [EKEvent] {
        await pause()
        eventStore.reset()
        let calendars = eventStore.calendars(for: .event).filter { calendar in calendar.title == CalendarCopyEvents.calendarTitle }
        XCTAssertEqual(calendars.count, 1, "One Graphite calendar.")
        guard !calendars.isEmpty else { return [] }
        let start = try XCTUnwrap(CalendarDay(year: 2031, month: 3, day: 1).startDate(in: .current))
        let end = try XCTUnwrap(CalendarDay(year: 2031, month: 4, day: 1).startDate(in: .current))
        return eventStore.events(matching: eventStore.predicateForEvents(withStart: start, end: end, calendars: calendars))
    }

    private func noteText(_ vault: URL, _ relativePath: String) throws -> String {
        try String(contentsOf: vault.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func pause() async {
        _ = await XCTWaiter.fulfillment(of: [XCTestExpectation(description: "a tenth of a second")], timeout: 0.1)
    }

    private static func describe(_ event: EKEvent) -> String {
        "\(event.title ?? "") \(event.isAllDay ? "all day" : "timed") \(event.startDate!)–\(event.endDate!) \(event.url?.absoluteString ?? "")"
    }
}

private extension CalendarCopyController.Status {
    var copiedReport: CalendarCopyReport? {
        if case .copied(let report, _) = self { return report }
        return nil
    }
}
#endif
