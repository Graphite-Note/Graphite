/**
 * File: CalendarMarkdownTests.swift
 * ---------------------------------
 * Layer: Tests
 * Description: Calendar days and months, a day's events as Markdown, the `{{events}}` template variable, event notes
 *              and the Calendar plugin's settings file.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

import XCTest
@testable import GraphiteCore
import GraphiteTestSupport

final class CalendarMarkdownTests: XCTestCase {
    /// Zurich, with weeks from Monday, so the tests do not depend on the machine's region.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Zurich") ?? .current
        calendar.locale = Locale(identifier: "en_GB")
        calendar.firstWeekday = 2
        return calendar
    }

    private func date(_ day: CalendarDay, hour: Int, minute: Int = 0) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: hour, minute: minute)))
    }

    private let november12 = CalendarDay(year: 2026, month: 11, day: 12)

    // MARK: Days and months

    func testADayReadsAndWritesTheTasksPluginsDateFormAndRefusesDaysNoCalendarHas() {
        XCTAssertEqual(CalendarDay(isoText: "2026-11-12"), november12)
        XCTAssertEqual(november12.isoText, "2026-11-12")
        XCTAssertEqual(CalendarDay(isoText: "2028-02-29"), CalendarDay(year: 2028, month: 2, day: 29))
        for refused in ["2026-02-30", "2026-13-01", "26-11-12", "2026-1-12", "2026/11/12", "today", ""] {
            XCTAssertNil(CalendarDay(isoText: refused), refused)
        }
        XCTAssertEqual(CalendarDay(year: 2026, month: 12, day: 31).adding(days: 1, in: calendar), CalendarDay(year: 2027, month: 1, day: 1))
        XCTAssertLessThan(CalendarDay(year: 2026, month: 11, day: 30), CalendarDay(year: 2026, month: 12, day: 1))
    }

    func testAMonthsWeeksStartOnTheFirstWeekdayAndAreCompletedByTheMonthsAround() {
        let november = CalendarMonth(year: 2026, month: 11)
        let weeks = november.weeks(in: calendar)

        // 1 November 2026 is a Sunday: the first week starts on Monday 26 October.
        XCTAssertEqual(weeks.count, 6)
        XCTAssertTrue(weeks.allSatisfy { week in week.count == 7 })
        XCTAssertEqual(weeks.first?.first, CalendarDay(year: 2026, month: 10, day: 26))
        XCTAssertEqual(weeks.first?.last, CalendarDay(year: 2026, month: 11, day: 1))
        XCTAssertEqual(weeks.last?.last, CalendarDay(year: 2026, month: 12, day: 6))
        XCTAssertEqual(weeks.joined().filter(november.contains).count, 30)
        XCTAssertEqual(november.weekdaySymbols(in: calendar), ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"])
        XCTAssertEqual(november.title(in: calendar), "November 2026")

        var sundayFirst = calendar
        sundayFirst.firstWeekday = 1
        XCTAssertEqual(november.weeks(in: sundayFirst).first?.first, CalendarDay(year: 2026, month: 11, day: 1), "A Sunday-first week starts on the 1st.")
        XCTAssertEqual(CalendarMonth(year: 2026, month: 2).weeks(in: sundayFirst).count, 4, "February 2026 fills exactly four weeks.")
    }

    func testMovingPastDecemberOrJanuaryChangesTheYear() {
        XCTAssertEqual(CalendarMonth(year: 2026, month: 12).adding(months: 1), CalendarMonth(year: 2027, month: 1))
        XCTAssertEqual(CalendarMonth(year: 2026, month: 1).adding(months: -1), CalendarMonth(year: 2025, month: 12))
        XCTAssertEqual(CalendarMonth(year: 2026, month: 1).adding(months: -13), CalendarMonth(year: 2024, month: 12))
        XCTAssertEqual(CalendarMonth(containing: november12), CalendarMonth(year: 2026, month: 11))
    }

    // MARK: A day's events

    func testADaysEventsAreListedAllDayFirstThenByTimeWithPlaceAndLinkInTheTemplatesTimeFormat() throws {
        let lecture = CalendarEvent(id: "lecture", calendarTitle: "Courses", title: "Computer Architecture", startDate: try date(november12, hour: 10, minute: 15),
                                    endDate: try date(november12, hour: 12), location: "ETZ E 6\nZurich")
        let standup = CalendarEvent(id: "standup", calendarTitle: "Work", title: "Standup", startDate: try date(november12, hour: 9), endDate: try date(november12, hour: 9, minute: 15))
        let conference = CalendarEvent(id: "conference", calendarTitle: "Work", title: "Conference", startDate: try date(november12, hour: 0),
                                       endDate: try date(november12.adding(days: 1, in: calendar), hour: 0), isAllDay: true)
        let tomorrow = CalendarEvent(id: "tomorrow", calendarTitle: "Work", title: "Tomorrow", startDate: try date(november12.adding(days: 1, in: calendar), hour: 9),
                                     endDate: try date(november12.adding(days: 1, in: calendar), hour: 10))

        let list = CalendarEventList.markdown(for: [lecture, tomorrow, standup, conference], on: november12, calendar: calendar, timeFormat: "HH:mm") { event in
            event.id == "lecture" ? "[[2026-11-12 Computer Architecture]]" : nil
        }

        XCTAssertEqual(list, """
            - **All day** Conference
            - **09:00–09:15** Standup
            - **10:15–12:00** Computer Architecture (ETZ E 6, Zurich) [[2026-11-12 Computer Architecture]]

            """)
        XCTAssertEqual(CalendarEventList.markdown(for: [standup], on: november12, calendar: calendar, timeFormat: "h:mm A"), "- **9:00 AM–9:15 AM** Standup\n")
        XCTAssertEqual(CalendarEventList.markdown(for: [tomorrow], on: november12, calendar: calendar, timeFormat: "HH:mm"), "", "A day without events lists nothing.")
    }

    func testAnEventAcrossMidnightShowsOnlyTheTimesThatFallOnTheDay() throws {
        let night = CalendarEvent(id: "night", calendarTitle: "Home", title: "Night\nTrain", startDate: try date(november12, hour: 22),
                                  endDate: try date(november12.adding(days: 1, in: calendar), hour: 6))
        let spanning = CalendarEvent(id: "spanning", calendarTitle: "Home", title: "", startDate: try date(november12.adding(days: -1, in: calendar), hour: 8),
                                     endDate: try date(november12.adding(days: 1, in: calendar), hour: 8))

        XCTAssertEqual(CalendarEventList.markdown(for: [night], on: november12, calendar: calendar, timeFormat: "HH:mm"), "- **22:00–** Night Train\n")
        XCTAssertEqual(CalendarEventList.markdown(for: [night], on: november12.adding(days: 1, in: calendar), calendar: calendar, timeFormat: "HH:mm"),
                       "- **–06:00** Night Train\n")
        XCTAssertEqual(CalendarEventList.markdown(for: [spanning], on: november12, calendar: calendar, timeFormat: "HH:mm"), "- **All day** Untitled Event\n",
                       "An event covering the whole day is all day on it.")
    }

    // MARK: The template variable

    func testEventsInATemplateAreFilledInWithoutAnEmptyLineAfterTheList() {
        let rendered = "# 2026-11-12\n\n## Agenda\n{{events}}\n## Notes\n"

        XCTAssertTrue(CalendarTemplateVariable.appears(in: rendered))
        XCTAssertTrue(CalendarTemplateVariable.appears(in: "{{ Events }}"))
        XCTAssertFalse(CalendarTemplateVariable.appears(in: "{{date}} {{title}}"))
        XCTAssertEqual(CalendarTemplateVariable.filled(rendered, eventList: "- **09:00** Standup\n"), "# 2026-11-12\n\n## Agenda\n- **09:00** Standup\n## Notes\n")
        XCTAssertEqual(CalendarTemplateVariable.filled("Today: {{events}}.", eventList: "- A\n"), "Today: - A\n.")
        XCTAssertEqual(CalendarTemplateVariable.filled("{{events}}\nEnd", eventList: ""), "\nEnd", "No events leave the line empty.")
    }

    func testTheOtherTemplateVariablesLeaveTheEventsVariableForTheCalendarToFill() {
        let rendered = TemplateRenderer.render("{{date}}\n{{events}}", title: "Note", date: Date(timeIntervalSince1970: 0), dateFormat: "YYYY", timeFormat: "HH:mm",
                                               timeZone: TimeZone(secondsFromGMT: 0) ?? .current)
        XCTAssertEqual(rendered, "1970\n{{events}}")
    }

    // MARK: Inserting a list

    func testABlockGoesOnLinesOfItsOwnAfterThePropertiesWithTheCursorAfterIt() {
        func inserted(_ text: String, at location: Int) -> (String, Int) {
            let edit = BlockInsertion.edit(inserting: "- A\n", into: text, at: NSRange(location: location, length: 0))
            return ((text as NSString).replacingCharacters(in: edit.range, with: edit.replacement), edit.selectionAfter.location)
        }
        XCTAssertEqual(inserted("abc\ndef", at: 3).0, "abc\n- A\ndef", "At a line's end, without an empty line after.")
        XCTAssertEqual(inserted("abc", at: 3).0, "abc\n- A\n")
        XCTAssertEqual(inserted("abc", at: 3).1, 8)
        XCTAssertEqual(inserted("abcdef", at: 3).0, "abc\n- A\ndef", "In the middle of a line, the rest goes on the next.")
        XCTAssertEqual(inserted("abc\n\nxyz", at: 4).0, "abc\n- A\nxyz")
        XCTAssertEqual(inserted("---\ntitle: A\n---\nBody", at: 2).0, "---\ntitle: A\n---\n- A\nBody", "Never inside the properties.")
        XCTAssertEqual(inserted("", at: 0).0, "- A\n")
    }

    // MARK: Event notes

    func testAnEventsNoteIsNamedByDayAndTitleAndKeepsTheEventAsProperties() throws {
        let event = CalendarEvent(id: "lecture", calendarTitle: "Courses", title: "VLSI 3: Lecture #4 [draft]", startDate: try date(november12, hour: 10, minute: 15),
                                  endDate: try date(november12, hour: 12), location: "ETZ E 6", attendees: ["Prof. Kim", "ana@example.com"])

        XCTAssertEqual(EventNote.fileStem(for: event, calendar: calendar), "2026-11-12 VLSI 3 Lecture 4 draft")
        XCTAssertEqual(EventNote.text(for: event, calendar: calendar), """
            ---
            date: 2026-11-12
            start: 2026-11-12T10:15
            end: 2026-11-12T12:00
            location: ETZ E 6
            attendees:
              - Prof. Kim
              - ana@example.com
            calendar: Courses
            ---

            # VLSI 3: Lecture #4 [draft]


            """)
        let parsedProperties = try XCTUnwrap(NoteProperties.parse(try XCTUnwrap(try MarkdownSemantics.parse(EventNote.text(for: event, calendar: calendar)).frontmatter)))
        XCTAssertEqual(parsedProperties.map(\.key), ["date", "start", "end", "location", "attendees", "calendar"], "Obsidian reads every property back.")
    }

    func testAnAllDayEventsNoteHasNoTimesAndALongTitleIsShortened() throws {
        let event = CalendarEvent(id: "day", calendarTitle: "", title: String(repeating: "Long ", count: 60), startDate: try date(november12, hour: 0),
                                  endDate: try date(november12.adding(days: 1, in: calendar), hour: 0), isAllDay: true)

        XCTAssertEqual(EventNote.properties(for: event, calendar: calendar).map(\.key), ["date"])
        XCTAssertLessThanOrEqual(EventNote.fileStem(for: event, calendar: calendar).count, 120)
        XCTAssertTrue(EventNote.fileStem(for: event, calendar: calendar).hasPrefix("2026-11-12 Long Long"))
    }

    // MARK: Settings

    func testTheCalendarSettingsFileKeepsKeysItDoesNotKnowAndReadsWrongTypesAsDefaults() throws {
        let written = Data(#"{"eventNoteFolders": {"Courses": "/Lectures/", "Work": 3}, "taskList": "Inbox", "futureKey": [1, 2]}"#.utf8)
        var settings = CalendarSettings(configurationData: written)

        XCTAssertEqual(settings.eventNoteFolders, ["Courses": "Lectures"])
        XCTAssertEqual(settings.taskListTitle, "Inbox")
        XCTAssertEqual(settings.eventNoteFolder(forCalendarTitled: "Courses"), try VaultPath("Lectures"))
        XCTAssertNil(settings.eventNoteFolder(forCalendarTitled: "Work"), "Without a folder of its own or a default, the vault's location for new notes.")
        settings.defaultEventNoteFolder = "Meetings"
        XCTAssertEqual(settings.eventNoteFolder(forCalendarTitled: "Work"), try VaultPath("Meetings"))

        let merged = try settings.mergedConfigurationData(existingData: written)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: merged) as? [String: Any])
        XCTAssertEqual(object["futureKey"] as? [Int], [1, 2])
        XCTAssertEqual(CalendarSettings(configurationData: merged), settings)
        XCTAssertThrowsError(try settings.mergedConfigurationData(existingData: Data("[1]".utf8)), "A file that is not an object is never overwritten.")
        XCTAssertEqual(CalendarSettings(configurationData: Data("not json".utf8)), CalendarSettings())
    }

    func testTheVaultStoreWritesTheCalendarSettingsIntoTheObsidianFolder() async throws {
        let vault = try TemporaryVault.make(prefix: "CalendarSettingsVault", for: self).root
        let store = VaultStore(root: vault)

        let missing = try await store.calendarSettings()
        XCTAssertEqual(missing, CalendarSettings())
        try await store.saveCalendarSettings(CalendarSettings(eventNoteFolders: ["Courses": "Lectures"]))

        XCTAssertTrue(FileManager.default.fileExists(atPath: vault.appendingPathComponent(".obsidian/graphite-calendar.json").path))
        let saved = try await store.calendarSettings()
        XCTAssertEqual(saved.eventNoteFolders, ["Courses": "Lectures"])
    }
}
