/**
 * File: CalendarItems.swift
 * -------------------------
 * Layer: Core
 * Description: The days, events, reminders and lists of Apple's Calendar and Reminders as plain values, so the rules
 *              that turn them into Markdown know nothing of EventKit.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

import Foundation

/// A day of the calendar, without a time or a time zone: the day a daily note is for, a
/// task's due date (`📅 2026-11-12`) or a day of the month view.
public struct CalendarDay: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The day `date` falls on in `calendar` (its time zone decides where midnight is).
    public init(_ date: Date, in calendar: Calendar) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: components.year ?? 1, month: components.month ?? 1, day: components.day ?? 1)
    }

    /// Reads `2026-11-12`, the form the Tasks plugin's date fields and Obsidian's date properties use; nil for any
    /// other text or a day no calendar has, such as `2026-02-30`.
    public init?(isoText: String) {
        let parts = isoText.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else { return nil }
        let candidate = CalendarDay(year: year, month: month, day: day)
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        guard let start = candidate.startDate(in: gregorian), CalendarDay(start, in: gregorian) == candidate else { return nil }
        self = candidate
    }

    /// `2026-11-12`.
    public var isoText: String { String(format: "%04ld-%02ld-%02ld", year, month, day) }
    public var description: String { isoText }

    /// The day's first moment in `calendar`.
    public func startDate(in calendar: Calendar) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    /// The day `offset` days later (earlier when negative).
    public func adding(days offset: Int, in calendar: Calendar) -> CalendarDay {
        guard let start = startDate(in: calendar), let moved = calendar.date(byAdding: .day, value: offset, to: start) else { return self }
        return CalendarDay(moved, in: calendar)
    }

    public static func < (leftDay: CalendarDay, rightDay: CalendarDay) -> Bool {
        (leftDay.year, leftDay.month, leftDay.day) < (rightDay.year, rightDay.month, rightDay.day)
    }
}

/// An event of the person's calendars, as EventKit reports it.
public struct CalendarEvent: Equatable, Hashable, Sendable, Identifiable {
    /// EventKit's identifier joined with the start, since every occurrence of a repeating event shares one identifier.
    public var id: String
    public var calendarTitle: String
    public var title: String
    public var startDate: Date
    public var endDate: Date
    public var isAllDay: Bool
    public var location: String?
    /// The attendees' names, or their addresses when a name is missing; the organizer first.
    public var attendees: [String]

    public init(id: String, calendarTitle: String, title: String, startDate: Date, endDate: Date, isAllDay: Bool = false,
                location: String? = nil, attendees: [String] = []) {
        self.id = id
        self.calendarTitle = calendarTitle
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.location = location
        self.attendees = attendees
    }

    /// The title on one line, or "Untitled Event" for an event with none.
    public var displayTitle: String {
        let oneLine = title.components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return oneLine.isEmpty ? "Untitled Event" : oneLine
    }

    /// Whether the event is under way at `moment`.
    public func isUnderWay(at moment: Date) -> Bool { startDate <= moment && moment < endDate }
}

/// A calendar of events or a list of reminders.
public struct CalendarList: Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

/// A reminder of the person's Reminders lists, as EventKit reports it.
public struct ReminderItem: Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    public var listTitle: String
    public var title: String
    public var dueDay: CalendarDay?
    public var isCompleted: Bool
    /// The link the reminder carries; Graphite's reminders point back at their task (`ReminderTaskLink`).
    public var link: URL?

    public init(id: String, listTitle: String, title: String, dueDay: CalendarDay? = nil, isCompleted: Bool = false, link: URL? = nil) {
        self.id = id
        self.listTitle = listTitle
        self.title = title
        self.dueDay = dueDay
        self.isCompleted = isCompleted
        self.link = link
    }
}

/// A reminder Graphite adds for a task.
public struct ReminderDraft: Equatable, Sendable {
    public var title: String
    public var dueDay: CalendarDay?
    /// The list's title; nil for the list Reminders adds new reminders to.
    public var listTitle: String?
    /// Opens the task's note in Graphite, and tells which task the reminder is for.
    public var link: URL

    public init(title: String, dueDay: CalendarDay?, listTitle: String?, link: URL) {
        self.title = title
        self.dueDay = dueDay
        self.listTitle = listTitle
        self.link = link
    }
}
