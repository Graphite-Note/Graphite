/**
 * File: BaseCalendarTests.swift
 * -----------------------------
 * Layer: Tests
 * Description: The calendar view of a base: Calendar Bases' keys read and written, each note's days, the lanes of a
 *              week, and moving a note's dates by days in the form the note wrote them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import XCTest
@testable import GraphiteCore

final class BaseCalendarTests: XCTestCase {
    private let zurich = TimeZone(identifier: "Europe/Zurich") ?? .current
    private var calendar: Calendar { BaseCalendarLayout.calendar(weekStartDay: .monday, timeZone: zurich, locale: Locale(identifier: "en_US_POSIX")) }

    private func day(_ text: String) throws -> CalendarDay { try XCTUnwrap(CalendarDay(isoText: text)) }

    private func date(_ text: String) throws -> BaseDate { try XCTUnwrap(BaseDateParsing.date(from: text, calendar: calendar)) }

    private func entry(_ name: String, start: String, end: String? = nil) throws -> BaseCalendarEntry {
        BaseCalendarEntry(path: try VaultPath(name + ".md"), start: try date(start), end: try end.map(date), calendar: calendar)
    }

    // MARK: The keys

    /// Calendar Bases' own sample (`test-vault/Events.base` of the plugin, 0.2.8).
    private let pluginSample = """
        filters:
          and:
            - file.hasTag("event")
        views:
          - type: calendar
            name: Calendar
            order:
              - file.name
              - tags
              - related
              - url
            startDate: note.date
            endDate: note.endDate
            weekStartDay: monday
          - type: cards
            name: Table
            order:
              - file.name
              - date
        """

    func testCalendarBasesSampleReadsAsANativeCalendarViewWithThePluginsKeys() throws {
        let definition = try BaseDefinition.parse(pluginSample)
        XCTAssertEqual(definition.views.map(\.type), [.calendar, .cards])
        let options = definition.views[0].calendar
        XCTAssertEqual(options.startDateProperty, .note("date"))
        XCTAssertEqual(options.endDateProperty, .note("endDate"))
        XCTAssertEqual(options.weekStartDay, .monday)
        XCTAssertTrue(options.writesNoteProperties)
        XCTAssertEqual(definition.views[0].pluginOptions, [:], "The keys are the view's own, not a plugin's.")
        XCTAssertEqual(BaseViewType(rawValue: "calendar"), .calendar)
        XCTAssertEqual(BaseViewType.calendar.rawValue, "calendar")
    }

    func testTheWeekStartsOnMondayUnlessTheFileNamesAnotherDayThePluginKnows() throws {
        func weekday(_ line: String) throws -> BaseCalendarWeekday {
            try BaseDefinition.parse("views:\n  - type: calendar\n    name: C\n    startDate: due\n\(line)").views[0].calendar.weekStartDay
        }
        XCTAssertEqual(try weekday(""), .monday)
        XCTAssertEqual(try weekday("    weekStartDay: sunday\n"), .sunday)
        XCTAssertEqual(try weekday("    weekStartDay: Saturday\n"), .saturday)
        XCTAssertEqual(try weekday("    weekStartDay: someday\n"), .monday)
        XCTAssertEqual(BaseCalendarWeekday.sunday.calendarWeekday, 1)
        XCTAssertEqual(BaseCalendarWeekday.saturday.calendarWeekday, 7)
    }

    func testOnlyNotePropertiesCanBeWrittenByAMove() throws {
        func options(_ start: String, _ end: String?) throws -> BaseCalendarOptions {
            try BaseDefinition.parse("views:\n  - type: calendar\n    name: C\n    startDate: \(start)\n" + (end.map { "    endDate: \($0)\n" } ?? "")).views[0].calendar
        }
        XCTAssertTrue(try options("due", nil).writesNoteProperties, "A bare name is a note property.")
        XCTAssertFalse(try options("file.ctime", nil).writesNoteProperties)
        XCTAssertFalse(try options("note.start", "formula.finish").writesNoteProperties)
        XCTAssertTrue(try options("note.start", "note.finish").writesNoteProperties)
    }

    func testTheEditorWritesThePluginsKeysAndLeavesTheRestAsWritten() throws {
        var editor = try BaseDefinitionEditor(yaml: pluginSample)
        try editor.setOption(BaseCalendarOptions.startDateKey, text: "note.deadline", forViewAt: 0)
        try editor.setOption(BaseCalendarOptions.endDateKey, text: nil, forViewAt: 0)
        try editor.setOption(BaseCalendarOptions.weekStartDayKey, text: BaseCalendarWeekday.sunday.rawValue, forViewAt: 0)
        let written = try editor.yaml()
        let reread = try BaseDefinition.parse(written).views[0].calendar
        XCTAssertEqual(reread, BaseCalendarOptions(startDateProperty: .note("deadline"), endDateProperty: nil, weekStartDay: .sunday))
        XCTAssertTrue(written.contains("file.hasTag(\"event\")"), "The filters stay.")
        XCTAssertFalse(written.contains("endDate"), "A cleared end removes its key.")
    }

    // MARK: Days

    func testAnEntryCoversItsDaysAndAnEndBeforeItsStartOrFarAwayIsBounded() throws {
        let trip = try entry("Trip", start: "2026-04-15", end: "2026-04-20")
        XCTAssertEqual(trip.firstDay, try day("2026-04-15"))
        XCTAssertEqual(trip.lastDay, try day("2026-04-20"))
        XCTAssertTrue(trip.covers(try day("2026-04-18")))
        XCTAssertFalse(trip.covers(try day("2026-04-21")))
        XCTAssertEqual(try entry("Backwards", start: "2026-04-15", end: "2026-04-10").lastDay, try day("2026-04-15"))
        XCTAssertEqual(try entry("Mistyped", start: "2026-01-01", end: "2036-01-01").lastDay, try day("2027-01-01"),
                       "At most 366 days are drawn.")
        let lecture = try entry("Lecture", start: "2026-04-15T10:15")
        XCTAssertNotNil(lecture.startTime)
        XCTAssertEqual(lecture.lastDay, lecture.firstDay)
    }

    func testEntriesOfAResultAreTheRowsWithAStartDateInDrawingOrder() throws {
        let definition = try BaseDefinition.parse("views:\n  - type: calendar\n    name: C\n    order: [title]\n    startDate: due\n    endDate: until\n")
        let records = [
            BaseTestRecords.record("Exam.md", yaml: "due: 2026-12-03T09:00\ntitle: Signals exam"),
            BaseTestRecords.record("Lab.md", yaml: "due: 2026-12-03"),
            BaseTestRecords.record("Week.md", yaml: "due: 2026-12-01\nuntil: 2026-12-05"),
            BaseTestRecords.record("Undated.md", yaml: "due: soon"),
        ]
        let environment = BaseEvaluationEnvironment(calendar: calendar)
        let result = BaseQueryEngine(definition: definition, environment: environment, thisRecord: nil).run(viewIndex: 0, records: records)
        let entries = BaseCalendarEntry.entries(of: result, calendar: calendar)
        XCTAssertEqual(entries.map(\.path.stem), ["Week", "Lab", "Exam"], "Earlier first days, then dates before times; text that is no date is left out.")
        let examRow = try XCTUnwrap(result.rows.first { row in row.path.stem == "Exam" })
        XCTAssertEqual(BaseCalendarEntry.title(of: examRow, columns: result.columns), "Signals exam", "The first property with a value titles the entry.")
        let labRow = try XCTUnwrap(result.rows.first { row in row.path.stem == "Lab" })
        XCTAssertEqual(BaseCalendarEntry.title(of: labRow, columns: result.columns), "Lab", "Without one, the file's name.")
    }

    // MARK: Weeks and lanes

    func testAMonthStartsOnTheViewsFirstWeekdayAndPlacesEachEntryOnOneLanePerWeek() throws {
        let entries = [try entry("Trip", start: "2026-04-15", end: "2026-04-20"), try entry("Lab", start: "2026-04-16"), try entry("Quiz", start: "2026-04-17")]
        let weeks = BaseCalendarLayout.weeks(of: CalendarMonth(year: 2026, month: 4), entries: entries.sorted(by: BaseCalendarEntry.drawingOrder), calendar: calendar)
        XCTAssertEqual(weeks.first?.days.first, try day("2026-03-30"), "April 2026 starts on a Wednesday: its first week begins on Monday the 30th.")
        XCTAssertEqual(weeks.count, 5)
        let thirdWeek = weeks[2]
        XCTAssertEqual(thirdWeek.days.first, try day("2026-04-13"))
        let tripInThirdWeek = try XCTUnwrap(thirdWeek.placements.first { placement in placement.entry.path.stem == "Trip" })
        XCTAssertEqual(tripInThirdWeek.firstColumn, 2)
        XCTAssertEqual(tripInThirdWeek.lastColumn, 6)
        XCTAssertEqual(tripInThirdWeek.lane, 0)
        XCTAssertTrue(tripInThirdWeek.continuesIntoLaterWeek)
        XCTAssertEqual(thirdWeek.placements.first { placement in placement.entry.path.stem == "Lab" }?.lane, 1)
        XCTAssertEqual(thirdWeek.placements.first { placement in placement.entry.path.stem == "Quiz" }?.lane, 1, "A lane free on its day is reused.")
        let tripInFourthWeek = try XCTUnwrap(weeks[3].placements.first { placement in placement.entry.path.stem == "Trip" })
        XCTAssertEqual(tripInFourthWeek.firstColumn, 0)
        XCTAssertEqual(tripInFourthWeek.lastColumn, 0)
        XCTAssertTrue(tripInFourthWeek.continuesFromEarlierWeek)
        XCTAssertEqual(thirdWeek.entries(on: try day("2026-04-16")).map(\.path.stem), ["Trip", "Lab"])
    }

    func testADayWithMoreEntriesThanLanesCountsTheHiddenOnes() throws {
        let entries = try (1...5).map { number in try entry("Task \(number)", start: "2026-04-16") }
        let week = BaseCalendarLayout.week(containing: try day("2026-04-16"), entries: entries, calendar: calendar)
        XCTAssertEqual(week.hiddenEntryCount(inColumn: 3, laneCount: 3), 2)
        XCTAssertEqual(week.hiddenEntryCount(inColumn: 2, laneCount: 3), 0)
    }

    func testASundayWeekStartsOnSunday() throws {
        let sundayCalendar = BaseCalendarLayout.calendar(weekStartDay: .sunday, timeZone: zurich)
        let days = BaseCalendarLayout.days(ofWeekContaining: try day("2026-04-16"), calendar: sundayCalendar)
        XCTAssertEqual(days.first, try day("2026-04-12"))
        XCTAssertEqual(days.last, try day("2026-04-18"))
    }

    // MARK: Moving

    func testAMoveKeepsADateADateAndATimeItsTimeOfDayAcrossDaylightSavingTime() throws {
        let due = try date("2026-03-27")
        XCTAssertEqual(BaseCalendarRescheduling.writtenValue(BaseCalendarRescheduling.moved(due, byDays: 3, calendar: calendar), calendar: calendar), .date("2026-03-30"))
        let lecture = try date("2026-03-27T10:15")
        let moved = BaseCalendarRescheduling.moved(lecture, byDays: 3, calendar: calendar)
        XCTAssertEqual(BaseCalendarRescheduling.writtenValue(moved, calendar: calendar), .dateTime("2026-03-30T10:15"),
                       "Zurich moves its clocks on 29 March: the lecture keeps 10:15.")
        let withSeconds = try date("2026-03-27T10:15:30")
        XCTAssertEqual(BaseCalendarRescheduling.writtenValue(BaseCalendarRescheduling.moved(withSeconds, byDays: -1, calendar: calendar), calendar: calendar),
                       .dateTime("2026-03-26T10:15:30"))
        XCTAssertEqual(BaseCalendarRescheduling.dayOffset(from: try day("2026-03-28"), to: try day("2026-04-02"), calendar: calendar), 5)
        XCTAssertEqual(BaseCalendarRescheduling.dayOffset(from: try day("2026-04-02"), to: try day("2026-03-28"), calendar: calendar), -5)
    }
}
