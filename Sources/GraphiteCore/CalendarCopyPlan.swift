/**
 * File: CalendarCopyPlan.swift
 * ----------------------------
 * Layer: Core
 * Description: The Calendar Copy core plugin's pure part: the event each dated note of a calendar view becomes, and
 *              the events to add, change and remove so the "Graphite" calendar matches the vault again.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import Foundation

/// When a copied event happens: over whole days, or from one moment to another.
public enum CopiedEventTiming: Hashable, Sendable {
    case allDay(firstDay: CalendarDay, lastDay: CalendarDay)
    case timed(start: Date, end: Date)
}

/// The event a note becomes in Apple Calendar.
public struct CopiedEvent: Hashable, Sendable {
    /// The note's `graphite://open` link: the event's URL, which opens the note from Calendar and pairs the event with
    /// its note at the next copy.
    public let link: String
    public let title: String
    public let timing: CopiedEventTiming
    public let notes: String

    public init(link: String, title: String, timing: CopiedEventTiming, notes: String) {
        self.link = link
        self.title = title
        self.timing = timing
        self.notes = notes
    }
}

/// An event of the "Graphite" calendar as the calendar holds it now.
public struct CalendarEventCopy: Hashable, Sendable {
    public let identifier: String
    /// The event's URL, nil for an event without one.
    public let link: String?
    public let title: String
    public let timing: CopiedEventTiming
    public let notes: String

    public init(identifier: String, link: String?, title: String, timing: CopiedEventTiming, notes: String) {
        self.identifier = identifier
        self.link = link
        self.title = title
        self.timing = timing
        self.notes = notes
    }

    var copiedEvent: CopiedEvent? { link.map { link in CopiedEvent(link: link, title: title, timing: timing, notes: notes) } }
}

/// An event of the calendar to write again with what its note gives now.
public struct CalendarCopyChange: Hashable, Sendable {
    public let identifier: String
    public let event: CopiedEvent
}

/// What a copy changes in the calendar. Only events whose link opens a note of the copied vault are ever changed or
/// removed: anything else in the calendar is the person's and is left alone.
public struct CalendarCopyPlan: Hashable, Sendable {
    public var additions: [CopiedEvent] = []
    public var changes: [CalendarCopyChange] = []
    /// Identifiers of events to remove: a note no longer in the view, or a second event for one note.
    public var removals: [String] = []

    public var isEmpty: Bool { additions.isEmpty && changes.isEmpty && removals.isEmpty }

    /// Compares the events the vault gives with those the calendar holds, by link.
    /// - Parameter ownedLinkPrefix: The start of every link into the copied vault (`CalendarCopyEvents.ownedLinkPrefix`).
    public static func plan(copying events: [CopiedEvent], over existing: [CalendarEventCopy], ownedLinkPrefix: String) -> CalendarCopyPlan {
        var plan = CalendarCopyPlan()
        var existingByLink: [String: [CalendarEventCopy]] = [:]
        for event in existing {
            guard let link = event.link, link.hasPrefix(ownedLinkPrefix) else { continue }
            existingByLink[link, default: []].append(event)
        }
        var copiedLinks = Set<String>()
        for event in events where copiedLinks.insert(event.link).inserted {
            guard let matches = existingByLink[event.link], let kept = matches.first(where: { match in match.copiedEvent == event }) ?? matches.first else {
                plan.additions.append(event)
                continue
            }
            if kept.copiedEvent != event { plan.changes.append(CalendarCopyChange(identifier: kept.identifier, event: event)) }
            // Two devices copying one vault into one iCloud calendar at the same moment can each add the event once.
            plan.removals += matches.filter { match in match.identifier != kept.identifier }.map(\.identifier)
        }
        for (link, matches) in existingByLink where !copiedLinks.contains(link) {
            plan.removals += matches.map(\.identifier)
        }
        plan.removals.sort()
        return plan
    }
}

/// The events a calendar view's notes become.
public enum CalendarCopyEvents {
    /// The calendar Graphite copies into, found by this title on a device that has it already.
    public static let calendarTitle = "Graphite"
    /// How long a timed event lasts when its note gives no end time.
    public static let defaultTimedDuration: TimeInterval = 60 * 60

    /// The days copied: from a year before `now` to three years after it, the four years EventKit reads at once.
    public static func window(around now: Date, calendar: Calendar) -> DateInterval {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .year, value: -1, to: today) ?? today
        let end = calendar.date(byAdding: .year, value: 3, to: today) ?? today
        return DateInterval(start: start, end: max(start, end))
    }

    /// The years searched when every copied event of a vault is removed, in the four-year spans EventKit reads at once:
    /// an event that left the copied window long ago is still found.
    public static func searchWindows(calendar: Calendar) -> [DateInterval] {
        stride(from: 1970, to: 2110, by: 4).compactMap { year in
            guard let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
                  let end = calendar.date(from: DateComponents(year: year + 4, month: 1, day: 1)) else { return nil }
            return DateInterval(start: start, end: end)
        }
    }

    /// The start of every link Graphite writes into events of this vault.
    public static func ownedLinkPrefix(vaultName: String) -> String {
        let sampleLink = VaultURI.openingLink(to: VaultPath.root, inVaultNamed: vaultName)
        guard let fileParameter = sampleLink.range(of: "&file=") else { return sampleLink }
        return String(sampleLink[..<fileParameter.upperBound])
    }

    /// The text of a copied event's notes, which says where it comes from and that edits made in Calendar do not last.
    public static func notes(forNoteAt path: VaultPath) -> String {
        "Copied by Graphite from \(path.rawValue). Change the note to change this event: edits made in Calendar are replaced at the next copy."
    }

    /// One event per entry that meets the window: all-day for a date, timed for a date with a time, until the end when
    /// it is a time after the start, else for `defaultTimedDuration`.
    public static func events(of entries: [BaseCalendarEntry], titles: [VaultPath: String], vaultName: String, window: DateInterval,
                              calendar: Calendar) -> [CopiedEvent] {
        let windowFirstDay = CalendarDay(window.start, in: calendar)
        let windowLastDay = CalendarDay(window.end, in: calendar)
        return entries.compactMap { entry in
            guard entry.lastDay >= windowFirstDay, entry.firstDay <= windowLastDay else { return nil }
            let timing: CopiedEventTiming
            if let startTime = entry.startTime {
                let writtenEndTime = entry.end.flatMap { end in end.hasTime && end.date > startTime ? end.date : nil }
                let endTime = writtenEndTime ?? startTime.addingTimeInterval(defaultTimedDuration)
                timing = .timed(start: startTime, end: endTime)
            } else {
                timing = .allDay(firstDay: entry.firstDay, lastDay: entry.lastDay)
            }
            let title = titles[entry.path] ?? BaseValue.file(entry.path).displayText
            return CopiedEvent(link: VaultURI.openingLink(to: entry.path, inVaultNamed: vaultName), title: title, timing: timing,
                               notes: notes(forNoteAt: entry.path))
        }
    }
}
