/**
 * File: CalendarCopyPlanTests.swift
 * ---------------------------------
 * Layer: Tests
 * Description: Calendar Copy's pure part: the event each dated note becomes, the plan that makes the calendar match
 *              the vault without touching anything else, and the vault's choice of base in its settings file.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import XCTest
@testable import GraphiteCore

final class CalendarCopyPlanTests: XCTestCase {
    private let zurich = TimeZone(identifier: "Europe/Zurich") ?? .current
    private var calendar: Calendar { BaseCalendarLayout.calendar(weekStartDay: .monday, timeZone: zurich) }
    private let prefix = CalendarCopyEvents.ownedLinkPrefix(vaultName: "Study Vault")

    private func day(_ text: String) throws -> CalendarDay { try XCTUnwrap(CalendarDay(isoText: text)) }

    private func entry(_ path: String, start: String, end: String? = nil) throws -> BaseCalendarEntry {
        let start = try XCTUnwrap(BaseDateParsing.date(from: start, calendar: calendar))
        let end = try end.map { text in try XCTUnwrap(BaseDateParsing.date(from: text, calendar: calendar)) }
        return BaseCalendarEntry(path: try VaultPath(path), start: start, end: end, calendar: calendar)
    }

    private func event(_ path: String, title: String, timing: CopiedEventTiming) throws -> CopiedEvent {
        CopiedEvent(link: VaultURI.openingLink(to: try VaultPath(path), inVaultNamed: "Study Vault"), title: title, timing: timing,
                    notes: CalendarCopyEvents.notes(forNoteAt: try VaultPath(path)))
    }

    private func existing(_ identifier: String, _ copied: CopiedEvent) -> CalendarEventCopy {
        CalendarEventCopy(identifier: identifier, link: copied.link, title: copied.title, timing: copied.timing, notes: copied.notes)
    }

    func testDatedNotesBecomeAllDayOrTimedEventsWithTheirLinkInsideTheWindow() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 26, hour: 12)))
        let window = CalendarCopyEvents.window(around: now, calendar: calendar)
        XCTAssertEqual(CalendarDay(window.start, in: calendar), try day("2025-11-26"))
        XCTAssertEqual(CalendarDay(window.end, in: calendar), try day("2029-11-26"))
        let entries = [
            try entry("Courses/Signals exam.md", start: "2026-12-03T09:00", end: "2026-12-03T11:00"),
            try entry("Courses/Lab report.md", start: "2026-12-01", end: "2026-12-04"),
            try entry("Courses/Quiz.md", start: "2026-12-02T14:00"),
            try entry("Old/Archived.md", start: "2020-01-01"),
        ]
        let events = CalendarCopyEvents.events(of: entries, titles: [try VaultPath("Courses/Signals exam.md"): "Signals"], vaultName: "Study Vault",
                                               window: window, calendar: calendar)
        XCTAssertEqual(events.count, 3, "A note dated outside the window is not copied.")
        XCTAssertEqual(events[0].link, "graphite://open?vault=Study%20Vault&file=Courses/Signals%20exam")
        XCTAssertEqual(events[0].title, "Signals")
        guard case .timed(let examStart, let examEnd) = events[0].timing else { return XCTFail("The exam has a time.") }
        XCTAssertEqual(examEnd.timeIntervalSince(examStart), 2 * 60 * 60)
        XCTAssertEqual(events[1].timing, .allDay(firstDay: try day("2026-12-01"), lastDay: try day("2026-12-04")))
        XCTAssertEqual(events[1].title, "Lab report", "Without a title, the note's name.")
        guard case .timed(let quizStart, let quizEnd) = events[2].timing else { return XCTFail("The quiz has a time.") }
        XCTAssertEqual(quizEnd.timeIntervalSince(quizStart), CalendarCopyEvents.defaultTimedDuration)
        XCTAssertTrue(events[1].notes.contains("Courses/Lab report.md"))
        XCTAssertTrue(events.allSatisfy { event in event.link.hasPrefix(prefix) })
    }

    func testThePlanAddsChangesAndRemovesOnlyGraphitesEventsOfThisVault() throws {
        let lab = try event("Lab.md", title: "Lab", timing: .allDay(firstDay: try day("2026-12-01"), lastDay: try day("2026-12-01")))
        let exam = try event("Exam.md", title: "Exam", timing: .allDay(firstDay: try day("2026-12-03"), lastDay: try day("2026-12-03")))
        let movedExam = try event("Exam.md", title: "Exam", timing: .allDay(firstDay: try day("2026-12-04"), lastDay: try day("2026-12-04")))
        let gone = try event("Gone.md", title: "Gone", timing: .allDay(firstDay: try day("2026-12-05"), lastDay: try day("2026-12-05")))
        let personal = CalendarEventCopy(identifier: "personal", link: nil, title: "Dentist", timing: exam.timing, notes: "")
        let otherVault = CalendarEventCopy(identifier: "other-vault", link: VaultURI.openingLink(to: try VaultPath("Gone.md"), inVaultNamed: "Work"),
                                           title: "Gone", timing: gone.timing, notes: "")
        let plan = CalendarCopyPlan.plan(copying: [lab, movedExam], over: [existing("exam", exam), existing("gone", gone), personal, otherVault],
                                         ownedLinkPrefix: prefix)
        XCTAssertEqual(plan.additions, [lab])
        XCTAssertEqual(plan.changes, [CalendarCopyChange(identifier: "exam", event: movedExam)], "An event edited in Calendar or a moved note is written again.")
        XCTAssertEqual(plan.removals, ["gone"], "The person's own event and another vault's are left alone.")
    }

    func testTheSameNoteCopiedTwiceKeepsTheMatchingEventAndRemovesTheRepeat() throws {
        let exam = try event("Exam.md", title: "Exam", timing: .allDay(firstDay: try day("2026-12-03"), lastDay: try day("2026-12-03")))
        let stale = CalendarEventCopy(identifier: "a", link: exam.link, title: "Old title", timing: exam.timing, notes: exam.notes)
        let plan = CalendarCopyPlan.plan(copying: [exam], over: [stale, existing("b", exam)], ownedLinkPrefix: prefix)
        XCTAssertEqual(plan, CalendarCopyPlan(additions: [], changes: [], removals: ["a"]))
        XCTAssertTrue(CalendarCopyPlan.plan(copying: [exam], over: [existing("b", exam)], ownedLinkPrefix: prefix).isEmpty, "A calendar that matches changes nothing.")
        XCTAssertEqual(CalendarCopyPlan.plan(copying: [], over: [existing("b", exam)], ownedLinkPrefix: prefix).removals, ["b"])
    }

    func testRemovalSearchesEveryYearInFourYearSpans() {
        let windows = CalendarCopyEvents.searchWindows(calendar: calendar)
        XCTAssertEqual(windows.count, 35)
        XCTAssertTrue(windows.allSatisfy { window in window.duration <= 4 * 366 * 24 * 60 * 60 })
        XCTAssertEqual(zip(windows, windows.dropFirst()).filter { earlier, later in earlier.end != later.start }.count, 0, "No gap between spans.")
    }

    // MARK: The vault's choice

    func testTheChoiceIsKeptUnderItsOwnKeyBesideTheCalendarPluginsSettings() throws {
        let calendarPluginFile = Data(#"{"taskList": "School", "defaultEventNoteFolder": "Lectures"}"#.utf8)
        let chosen = CalendarCopySettings(basePath: try VaultPath("Courses/Deadlines.base"), viewName: "Calendar")
        let written = try chosen.mergedConfigurationData(existingData: calendarPluginFile)
        XCTAssertEqual(CalendarCopySettings(configurationData: written), chosen)
        XCTAssertEqual(CalendarSettings(configurationData: written).taskListTitle, "School", "The Calendar plugin's keys stay.")
        XCTAssertEqual(CalendarSettings(configurationData: written).defaultEventNoteFolder, "Lectures")
        XCTAssertFalse(CalendarCopySettings(configurationData: calendarPluginFile).isChosen)
        XCTAssertFalse(CalendarCopySettings(configurationData: Data("not json".utf8)).isChosen)
        let none = try CalendarCopySettings().mergedConfigurationData(existingData: written)
        XCTAssertFalse(CalendarCopySettings(configurationData: none).isChosen)
        XCTAssertThrowsError(try chosen.mergedConfigurationData(existingData: Data("[1]".utf8)), "A file that is not an object is left as it is.")
    }
}
