/**
 * File: CalendarMarkdown.swift
 * ----------------------------
 * Layer: Core
 * Description: A day's events as a Markdown list, the `{{events}}` template variable, and the note made from an event:
 *              its name, properties and heading.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

import Foundation

/// A day's events as a Markdown list, which a note keeps as ordinary text:
///
///     - **All day** Conference
///     - **09:00–10:30** Lecture (Room 101) [[2026-11-12 Lecture]]
///
/// The time is written in the Templates plugin's time format (`HH:mm` by default), and an event that already has a
/// note links to it.
public enum CalendarEventList {
    /// The events that take place on `day`, all-day events first, then by start and title.
    public static func events(_ events: [CalendarEvent], on day: CalendarDay, calendar: Calendar) -> [CalendarEvent] {
        guard let dayStart = day.startDate(in: calendar), let nextDayStart = day.adding(days: 1, in: calendar).startDate(in: calendar) else { return [] }
        return events
            .filter { event in
                // An event of no length counts on the day it is at.
                event.startDate < nextDayStart && (event.endDate > dayStart || (event.endDate == event.startDate && event.startDate >= dayStart))
            }
            .sorted { first, second in
                let firstIsAllDay = isAllDay(first, dayStart: dayStart, nextDayStart: nextDayStart)
                let secondIsAllDay = isAllDay(second, dayStart: dayStart, nextDayStart: nextDayStart)
                if firstIsAllDay != secondIsAllDay { return firstIsAllDay }
                if first.startDate != second.startDate { return first.startDate < second.startDate }
                return first.displayTitle.localizedStandardCompare(second.displayTitle) == .orderedAscending
            }
    }

    /// The list for `day`, one line per event, each ending with a line break; empty when the day has no event.
    /// - Parameter linkForEvent: The link to the event's note when it has one, written as the vault writes links.
    public static func markdown(for events: [CalendarEvent], on day: CalendarDay, calendar: Calendar, timeFormat: String,
                                language: MomentDateLanguage = .english, linkForEvent: (CalendarEvent) -> String? = { _ in nil }) -> String {
        let formatTime = { (date: Date) in MomentDateFormat.string(from: date, format: timeFormat, timeZone: calendar.timeZone, language: language) }
        return Self.events(events, on: day, calendar: calendar).map { event in
            var line = "- **" + timeText(of: event, on: day, calendar: calendar, formatTime: formatTime) + "** " + event.displayTitle
            if let location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines), !location.isEmpty {
                line += " (" + location.components(separatedBy: .newlines).joined(separator: ", ") + ")"
            }
            if let link = linkForEvent(event) { line += " " + link }
            return line + "\n"
        }.joined()
    }

    /// "All day", "09:00–10:30", or one side only for an event that began the day before or ends the day after, with
    /// each time written by `formatTime`.
    public static func timeText(of event: CalendarEvent, on day: CalendarDay, calendar: Calendar, formatTime: (Date) -> String) -> String {
        guard let dayStart = day.startDate(in: calendar), let nextDayStart = day.adding(days: 1, in: calendar).startDate(in: calendar) else { return "" }
        if isAllDay(event, dayStart: dayStart, nextDayStart: nextDayStart) { return "All day" }
        let startText = event.startDate >= dayStart ? formatTime(event.startDate) : ""
        let endText = event.endDate <= nextDayStart ? formatTime(event.endDate) : ""
        if event.endDate == event.startDate || startText == endText { return startText }
        return startText + "–" + endText
    }

    private static func isAllDay(_ event: CalendarEvent, dayStart: Date, nextDayStart: Date) -> Bool {
        event.isAllDay || (event.startDate <= dayStart && event.endDate >= nextDayStart)
    }
}

/// `{{events}}`, Graphite's template variable for the day's events, filled in with `CalendarEventList` when a daily
/// note is made from its template or a template is inserted. Obsidian leaves the variable as it is written.
public enum CalendarTemplateVariable {
    private static let variablePattern = CalendarTemplateVariablePattern.events.compiled()

    public static func appears(in template: String) -> Bool {
        variablePattern.firstMatch(in: template, range: NSRange(location: 0, length: (template as NSString).length)) != nil
    }

    /// `rendered` with each `{{events}}` replaced by `eventList`. A list that ends with a line break loses it when the
    /// variable is followed by one already, so a template line holding only the variable leaves no empty line.
    public static func filled(_ rendered: String, eventList: String) -> String {
        let source = rendered as NSString
        var result = ""
        var location = 0
        for match in variablePattern.matches(in: rendered, range: NSRange(location: 0, length: source.length)) {
            result += source.substring(with: NSRange(location: location, length: match.range.location - location))
            location = NSMaxRange(match.range)
            let followedByLineBreak = location < source.length && source.substring(with: NSRange(location: location, length: 1)) == "\n"
            result += followedByLineBreak && eventList.hasSuffix("\n") ? String(eventList.dropLast()) : eventList
        }
        return result + source.substring(from: location)
    }
}

/// The constant pattern of `CalendarTemplateVariable`; `StaticPatternTests` compiles every case.
enum CalendarTemplateVariablePattern: String, StaticPatternSet {
    case events = #"\{\{\s*events\s*\}\}"#

    var options: NSRegularExpression.Options {
        switch self {
        case .events: [.caseInsensitive]
        }
    }
}

/// The note made from an event, for a meeting or a lecture: named after the day and the event, with the event's
/// date, times, place, attendees and calendar as properties Obsidian reads.
public enum EventNote {
    /// Characters that cannot be in a file name on one of the platforms, or that Obsidian's links cannot name.
    private static let reservedCharacters = CharacterSet(charactersIn: "/\\:*?\"<>|#^[]")

    /// "2026-11-12 Lecture", so a course's notes sort by day.
    public static func fileStem(for event: CalendarEvent, calendar: Calendar) -> String {
        let title = event.displayTitle.components(separatedBy: reservedCharacters).joined(separator: " ")
            .split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        let stem = CalendarDay(event.startDate, in: calendar).isoText + " " + (title.isEmpty ? "Event" : title)
        // A name of at most about 120 characters stays well within every file system's limit.
        return String(stem.prefix(maximumStemLength)).trimmingCharacters(in: .whitespaces)
    }

    private static let maximumStemLength = 120

    /// The event's properties: `date`, `start` and `end` (not for an all-day event), `location`, `attendees` and
    /// `calendar`, each only when the event has it.
    public static func properties(for event: CalendarEvent, calendar: Calendar) -> [NoteProperty] {
        var properties = [NoteProperty(key: "date", value: .date(CalendarDay(event.startDate, in: calendar).isoText))]
        if !event.isAllDay {
            properties.append(NoteProperty(key: "start", value: .dateTime(dateTimeText(event.startDate, calendar: calendar))))
            properties.append(NoteProperty(key: "end", value: .dateTime(dateTimeText(event.endDate, calendar: calendar))))
        }
        if let location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines), !location.isEmpty {
            properties.append(NoteProperty(key: "location", value: .text(location.components(separatedBy: .newlines).joined(separator: ", "))))
        }
        if !event.attendees.isEmpty { properties.append(NoteProperty(key: "attendees", value: .list(event.attendees))) }
        if !event.calendarTitle.isEmpty { properties.append(NoteProperty(key: "calendar", value: .text(event.calendarTitle))) }
        return properties
    }

    /// The new note's text: the properties, then the event's title as its heading.
    public static func text(for event: CalendarEvent, calendar: Calendar) -> String {
        "---\n" + NoteProperties.serialize(properties(for: event, calendar: calendar)) + "---\n\n# " + event.displayTitle + "\n\n"
    }

    /// `2026-11-12T09:00`, the form of Obsidian's Date & Time properties.
    static func dateTimeText(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(format: "%04ld-%02ld-%02ldT%02ld:%02ld", components.year ?? 0, components.month ?? 0, components.day ?? 0,
                      components.hour ?? 0, components.minute ?? 0)
    }
}

/// A block of lines inserted at the cursor, such as a list of events or tasks: on lines of its own, after the note's
/// properties, with the cursor after it.
public enum BlockInsertion {
    public static func edit(inserting block: String, into text: String, at selection: NSRange) -> MarkdownTextEdit {
        let source = text as NSString
        let frontmatterLength = FrontmatterLocator.length(in: source)
        let location = min(max(selection.location, frontmatterLength), source.length)
        let endLocation = min(max(location, NSMaxRange(selection)), source.length)
        let startsLine = location == 0 || source.character(at: location - 1) == lineFeed
        var insertion = (startsLine ? "" : "\n") + block
        if !insertion.hasSuffix("\n") { insertion += "\n" }
        // A line break after the cursor ends the block's last line already.
        if endLocation < source.length, source.character(at: endLocation) == lineFeed { insertion.removeLast() }
        let insertionLength = (insertion as NSString).length
        return MarkdownTextEdit(range: NSRange(location: location, length: endLocation - location), replacement: insertion,
                                selectionAfter: NSRange(location: location + insertionLength, length: 0))
    }

    private static let lineFeed = unichar(10)
}
