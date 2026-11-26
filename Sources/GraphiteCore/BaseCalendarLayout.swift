/**
 * File: BaseCalendarLayout.swift
 * ------------------------------
 * Layer: Core
 * Description: Where a calendar view puts each note: its days from the view's dates, the weeks of a month or a
 *              week, and the lane of each entry in a week, so a note spanning days keeps one row.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import Foundation

/// One note on a calendar: the days it covers and the dates they were read from.
public struct BaseCalendarEntry: Hashable, Sendable, Identifiable {
    /// The longest span drawn, so a mistyped end year does not lay out decades of days.
    public static let maximumSpanDays = 366

    public let path: VaultPath
    public let start: BaseDate
    /// The end as written, nil when the view has no end property or the note no end date.
    public let end: BaseDate?
    public let firstDay: CalendarDay
    /// The last day drawn: the end's day, or the first day for an end before the start or none.
    public let lastDay: CalendarDay
    public var id: VaultPath { path }

    public init(path: VaultPath, start: BaseDate, end: BaseDate?, calendar: Calendar) {
        self.path = path
        self.start = start
        self.end = end
        firstDay = CalendarDay(start.date, in: calendar)
        let endDay = end.map { endDate in CalendarDay(endDate.date, in: calendar) } ?? firstDay
        let cappedEndDay = min(endDay, firstDay.adding(days: Self.maximumSpanDays - 1, in: calendar))
        lastDay = max(firstDay, cappedEndDay)
    }

    /// Whether the entry covers `day`.
    public func covers(_ day: CalendarDay) -> Bool { firstDay <= day && day <= lastDay }

    /// The time of day the entry starts at, nil for a date without a time.
    public var startTime: Date? { start.hasTime ? start.date : nil }

    /// The title Calendar Bases gives an entry: the first of the view's properties that holds a value, on one line, else
    /// the file's name. The file's name is shown as a board's card shows it, without `.md`.
    /// - Parameter columns: The result's columns, aligned with the row's cells.
    public static func title(of row: BaseResultRow, columns: [BaseColumn]) -> String {
        for (cell, column) in zip(row.cells, columns) {
            if column.property == .file("name") || column.property == .file("basename") { return BaseValue.file(row.path).displayText }
            guard let value = cell.value, !value.isEmptyValue else { continue }
            let firstLine = value.displayText.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespaces) ?? ""
            if !firstLine.isEmpty { return firstLine }
        }
        return BaseValue.file(row.path).displayText
    }

    /// The calendar's entries of a result: every row with a start date, in the order the calendar draws them.
    public static func entries(of result: BaseQueryResult, calendar: Calendar) -> [BaseCalendarEntry] {
        result.rows.compactMap { row in
            row.presentation.calendarStart.map { start in
                BaseCalendarEntry(path: row.path, start: start, end: row.presentation.calendarEnd, calendar: calendar)
            }
        }.sorted(by: drawingOrder)
    }

    /// The order entries take in a day and in a week's lanes: earlier first days, then longer spans, then dates
    /// without a time before timed ones, then earlier times, then the path, so the order never changes between runs.
    public static func drawingOrder(_ first: BaseCalendarEntry, _ second: BaseCalendarEntry) -> Bool {
        if first.firstDay != second.firstDay { return first.firstDay < second.firstDay }
        if first.lastDay != second.lastDay { return first.lastDay > second.lastDay }
        switch (first.startTime, second.startTime) {
        case (nil, .some): return true
        case (.some, nil): return false
        case (.some(let firstTime), .some(let secondTime)) where firstTime != secondTime: return firstTime < secondTime
        default: return first.path.rawValue < second.path.rawValue
        }
    }
}

/// An entry's place in one week: the columns it covers and its lane (row) among the week's entries.
public struct BaseCalendarPlacement: Hashable, Sendable {
    public let entry: BaseCalendarEntry
    /// The first and last of the week's seven columns it covers, from 0.
    public let firstColumn: Int
    public let lastColumn: Int
    public let lane: Int
    /// Whether the entry began before this week, or goes on after it.
    public let continuesFromEarlierWeek: Bool
    public let continuesIntoLaterWeek: Bool
}

/// Seven days with the entries placed over them.
public struct BaseCalendarWeek: Hashable, Sendable {
    public let days: [CalendarDay]
    public let placements: [BaseCalendarPlacement]

    /// The entries of one day, in drawing order.
    public func entries(on day: CalendarDay) -> [BaseCalendarEntry] {
        placements.filter { placement in placement.entry.covers(day) }.sorted { first, second in first.lane < second.lane }.map(\.entry)
    }

    /// How many of a day's entries lie in lanes from `laneCount` on, which a grid of that many lanes does not draw.
    public func hiddenEntryCount(inColumn column: Int, laneCount: Int) -> Int {
        placements.filter { placement in placement.lane >= laneCount && placement.firstColumn <= column && column <= placement.lastColumn }.count
    }
}

/// The weeks a calendar view draws.
public enum BaseCalendarLayout {
    /// The calendar a view lays out in: Gregorian, the device's time zone, weeks from the view's first weekday.
    public static func calendar(weekStartDay: BaseCalendarWeekday, timeZone: TimeZone = .current, locale: Locale = .current) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = locale
        calendar.firstWeekday = weekStartDay.calendarWeekday
        return calendar
    }

    /// The weeks of `month`, the first and last completed with days of the months beside it.
    public static func weeks(of month: CalendarMonth, entries: [BaseCalendarEntry], calendar: Calendar) -> [BaseCalendarWeek] {
        month.weeks(in: calendar).map { days in week(days: days, entries: entries) }
    }

    /// The week holding `day`.
    public static func week(containing day: CalendarDay, entries: [BaseCalendarEntry], calendar: Calendar) -> BaseCalendarWeek {
        week(days: days(ofWeekContaining: day, calendar: calendar), entries: entries)
    }

    /// The seven days of the week holding `day`, from the calendar's first weekday.
    public static func days(ofWeekContaining day: CalendarDay, calendar: Calendar) -> [CalendarDay] {
        guard let date = day.startDate(in: calendar) else { return [day] }
        let leadingDayCount = (calendar.component(.weekday, from: date) - calendar.firstWeekday + 7) % 7
        let firstDay = day.adding(days: -leadingDayCount, in: calendar)
        return (0..<7).map { offset in firstDay.adding(days: offset, in: calendar) }
    }

    /// Places the entries that meet `days` in lanes: each takes the lowest lane free over all of its columns, in
    /// drawing order, so an entry spanning days keeps one lane through the week.
    static func week(days: [CalendarDay], entries: [BaseCalendarEntry]) -> BaseCalendarWeek {
        guard let weekFirstDay = days.first, let weekLastDay = days.last else { return BaseCalendarWeek(days: days, placements: []) }
        let meetingEntries = entries.filter { entry in entry.firstDay <= weekLastDay && entry.lastDay >= weekFirstDay }.sorted { first, second in
            // Within a week an entry that began earlier starts at the first column, like one starting there.
            let firstStart = max(first.firstDay, weekFirstDay), secondStart = max(second.firstDay, weekFirstDay)
            if firstStart != secondStart { return firstStart < secondStart }
            return BaseCalendarEntry.drawingOrder(first, second)
        }
        var occupiedLanesByColumn = Array(repeating: Set<Int>(), count: days.count)
        var placements: [BaseCalendarPlacement] = []
        for entry in meetingEntries {
            let firstColumn = days.firstIndex { day in day >= entry.firstDay } ?? 0
            let lastColumn = days.lastIndex { day in day <= entry.lastDay } ?? days.count - 1
            let columns = firstColumn...lastColumn
            var lane = 0
            while columns.contains(where: { column in occupiedLanesByColumn[column].contains(lane) }) { lane += 1 }
            for column in columns { occupiedLanesByColumn[column].insert(lane) }
            placements.append(BaseCalendarPlacement(entry: entry, firstColumn: firstColumn, lastColumn: lastColumn, lane: lane,
                                                    continuesFromEarlierWeek: entry.firstDay < weekFirstDay,
                                                    continuesIntoLaterWeek: entry.lastDay > weekLastDay))
        }
        return BaseCalendarWeek(days: days, placements: placements)
    }
}

/// Moving a note to another day of its calendar: both of its dates shift by the same number of days, each keeping the
/// form the note wrote, a date as a date and a date with a time with its time of day.
public enum BaseCalendarRescheduling {
    /// `date` moved by `dayOffset` days, its time of day kept across a change of daylight saving time.
    public static func moved(_ date: BaseDate, byDays dayOffset: Int, calendar: Calendar) -> BaseDate {
        guard dayOffset != 0, let movedDate = calendar.date(byAdding: .day, value: dayOffset, to: date.date) else { return date }
        return BaseDate(date: movedDate, hasTime: date.hasTime)
    }

    /// The value written back: `2026-12-03` for a date, `2026-12-03T14:00` for a time on the minute (the form
    /// Obsidian's date and time property writes), with the seconds otherwise.
    public static func writtenValue(_ date: BaseDate, calendar: Calendar) -> PropertyValue {
        guard date.hasTime else { return .date(CalendarDay(date.date, in: calendar).isoText) }
        let seconds = calendar.component(.second, from: date.date)
        let pattern = seconds == 0 ? "YYYY-MM-DD[T]HH:mm" : "YYYY-MM-DD[T]HH:mm:ss"
        return .dateTime(BaseDateFormatting.format(date.date, pattern: pattern, calendar: calendar))
    }

    /// The days between the entry's day under the pointer and the day it was dropped on.
    public static func dayOffset(from grabbedDay: CalendarDay, to droppedDay: CalendarDay, calendar: Calendar) -> Int {
        guard let grabbedDate = grabbedDay.startDate(in: calendar), let droppedDate = droppedDay.startDate(in: calendar) else { return 0 }
        return calendar.dateComponents([.day], from: grabbedDate, to: droppedDate).day ?? 0
    }
}
