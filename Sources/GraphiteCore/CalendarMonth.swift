/**
 * File: CalendarMonth.swift
 * -------------------------
 * Layer: Core
 * Description: A month as the calendar panel draws it: its weeks from the device's first weekday, with the days of
 *              the months around it that complete the first and last weeks.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

import Foundation

/// A month of a year, which the calendar panel shows one at a time.
public struct CalendarMonth: Hashable, Sendable {
    public let year: Int
    /// 1 for January.
    public let month: Int

    public init(year: Int, month: Int) {
        // A month outside 1…12 is carried into the year, as moving past December does.
        let monthIndex = year * 12 + (month - 1)
        self.year = Int((Double(monthIndex) / 12).rounded(.down))
        self.month = monthIndex - self.year * 12 + 1
    }

    public init(containing day: CalendarDay) {
        self.init(year: day.year, month: day.month)
    }

    public func adding(months offset: Int) -> CalendarMonth {
        CalendarMonth(year: year, month: month + offset)
    }

    public func contains(_ day: CalendarDay) -> Bool { day.year == year && day.month == month }

    /// The month's weeks, each of seven days starting on `calendar.firstWeekday`; the first and last weeks are
    /// completed with days of the months before and after. Four to six weeks, as the month needs.
    public func weeks(in calendar: Calendar) -> [[CalendarDay]] {
        guard let firstDate = CalendarDay(year: year, month: month, day: 1).startDate(in: calendar),
              let dayCount = calendar.range(of: .day, in: .month, for: firstDate)?.count else { return [] }
        let weekday = calendar.component(.weekday, from: firstDate)
        let leadingDayCount = (weekday - calendar.firstWeekday + 7) % 7
        let shownDayCount = Int((Double(leadingDayCount + dayCount) / 7).rounded(.up)) * 7
        let firstShownDay = CalendarDay(year: year, month: month, day: 1).adding(days: -leadingDayCount, in: calendar)
        guard let firstShownDate = firstShownDay.startDate(in: calendar) else { return [] }
        let days = (0..<shownDayCount).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: firstShownDate).map { date in CalendarDay(date, in: calendar) }
        }
        return stride(from: 0, to: days.count, by: 7).map { weekStart in Array(days[weekStart..<min(weekStart + 7, days.count)]) }
    }

    /// The weekday names over the columns, from `calendar.firstWeekday`, in the calendar's own short form ("Mon").
    public func weekdaySymbols(in calendar: Calendar) -> [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        guard symbols.count == 7 else { return symbols }
        return (0..<7).map { offset in symbols[(calendar.firstWeekday - 1 + offset) % 7] }
    }

    /// "November 2026", in the calendar's language.
    public func title(in calendar: Calendar) -> String {
        guard let firstDate = CalendarDay(year: year, month: month, day: 1).startDate(in: calendar) else { return "\(year)" }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = calendar.locale ?? .current
        formatter.setLocalizedDateFormatFromTemplate("MMMMyyyy")
        return formatter.string(from: firstDate)
    }
}
