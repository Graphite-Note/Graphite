/**
 * File: CalendarCopyStore.swift
 * -----------------------------
 * Layer: Apple
 * Description: The Calendar Copy core plugin's calendar through EventKit: the "Graphite" calendar found or made, its
 *              events read in a window, and a copy's additions, changes and removals written in one commit.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import EventKit
import GraphiteCore

/// What a copy did to the calendar.
public struct CalendarCopyReport: Equatable, Sendable {
    public var addedCount = 0
    public var changedCount = 0
    public var removedCount = 0

    public init(addedCount: Int = 0, changedCount: Int = 0, removedCount: Int = 0) {
        self.addedCount = addedCount
        self.changedCount = changedCount
        self.removedCount = removedCount
    }
}

public enum CalendarCopyStoreError: LocalizedError, Equatable {
    case accessRefused
    /// The device has no source in which a calendar can be made, as with every account's calendars turned off.
    case noCalendarSource
    case calendarNotSaved(String)

    public var errorDescription: String? {
        switch self {
        case .accessRefused: "Graphite cannot use your calendars. Allow full access in Settings › Privacy & Security › Calendars."
        case .noCalendarSource: "This device has no calendar account Graphite can add a calendar to. Turn on iCloud Calendars, or another account, in Settings."
        case .calendarNotSaved(let reason): "Graphite could not make its calendar: \(reason)"
        }
    }
}

/// The calendar Calendar Copy writes. A protocol because the tests answer for it: no test touches the calendars of the
/// machine it runs on.
public protocol CalendarCopyStore: Sendable {
    /// Whether Graphite may read and write the person's calendars; never asks.
    func access() async -> CalendarAccess
    /// Asks the person for full access when they never answered.
    func requestAccess() async -> CalendarAccess
    /// The "Graphite" calendar: the one with `knownIdentifier`, else one titled `title` that Graphite may change, else a
    /// new one. Returns its identifier, which the device keeps.
    func calendar(knownIdentifier: String?, title: String) async throws -> String
    /// The calendar's events that meet `window`; an empty list when the calendar is gone.
    func events(inCalendar calendarIdentifier: String, during window: DateInterval) async throws -> [CalendarEventCopy]
    /// Writes the plan into the calendar and commits it once.
    func apply(_ plan: CalendarCopyPlan, inCalendar calendarIdentifier: String) async throws -> CalendarCopyReport
    /// Removes the calendar when no event is left in it, in any year from 1970 to 2109. Returns whether it was removed.
    func removeCalendarIfEmpty(_ calendarIdentifier: String) async throws -> Bool
}

/// Calendar Copy's calendar in the system's Calendar. It keeps an event store of its own, made at its first use, so
/// its reads and writes run on this actor, off the main thread, and a launch that copies nothing makes none.
public actor LiveCalendarCopyStore: CalendarCopyStore {
    private var eventStore: EKEventStore?

    public init() {}

    public func access() -> CalendarAccess {
        LiveCalendarStore.access(of: EKEventStore.authorizationStatus(for: .event))
    }

    public func requestAccess() async -> CalendarAccess {
        guard access() == .notAsked else { return access() }
        do {
            _ = try await madeEventStore().requestFullAccessToEvents()
        } catch {
            return .notAsked // The question could not be shown; the person is asked again next time.
        }
        return access()
    }

    public func calendar(knownIdentifier: String?, title: String) throws -> String {
        let store = try readableStore()
        if let knownIdentifier, let known = store.calendar(withIdentifier: knownIdentifier), known.allowsContentModifications {
            return known.calendarIdentifier
        }
        let calendars = store.calendars(for: .event).filter { calendar in calendar.title == title && calendar.allowsContentModifications }
        let preferredSource = Self.preferredSource(in: store)
        if let found = calendars.first(where: { calendar in calendar.source == preferredSource }) ?? calendars.first {
            return found.calendarIdentifier
        }
        guard let preferredSource else { throw CalendarCopyStoreError.noCalendarSource }
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = title
        calendar.source = preferredSource
        do {
            try store.saveCalendar(calendar, commit: true)
        } catch {
            throw CalendarCopyStoreError.calendarNotSaved(error.localizedDescription)
        }
        return calendar.calendarIdentifier
    }

    public func events(inCalendar calendarIdentifier: String, during window: DateInterval) throws -> [CalendarEventCopy] {
        let store = try readableStore()
        guard let calendar = store.calendar(withIdentifier: calendarIdentifier) else { return [] }
        let predicate = store.predicateForEvents(withStart: window.start, end: window.end, calendars: [calendar])
        let dayCalendar = Self.dayCalendar
        return store.events(matching: predicate).compactMap { event in
            guard let identifier = event.eventIdentifier else { return nil }
            return CalendarEventCopy(identifier: identifier, link: event.url?.absoluteString, title: event.title ?? "",
                                     timing: Self.timing(of: event, in: dayCalendar), notes: event.notes ?? "")
        }
    }

    public func apply(_ plan: CalendarCopyPlan, inCalendar calendarIdentifier: String) throws -> CalendarCopyReport {
        let store = try readableStore()
        guard let calendar = store.calendar(withIdentifier: calendarIdentifier) else { return CalendarCopyReport() }
        var report = CalendarCopyReport()
        for removal in plan.removals {
            guard let event = store.event(withIdentifier: removal), event.calendar?.calendarIdentifier == calendarIdentifier else { continue }
            try store.remove(event, span: .thisEvent, commit: false)
            report.removedCount += 1
        }
        for change in plan.changes {
            guard let event = store.event(withIdentifier: change.identifier), event.calendar?.calendarIdentifier == calendarIdentifier else { continue }
            Self.write(change.event, into: event)
            try store.save(event, span: .thisEvent, commit: false)
            report.changedCount += 1
        }
        for addition in plan.additions {
            let event = EKEvent(eventStore: store)
            event.calendar = calendar
            Self.write(addition, into: event)
            try store.save(event, span: .thisEvent, commit: false)
            report.addedCount += 1
        }
        if report != CalendarCopyReport() { try store.commit() }
        return report
    }

    public func removeCalendarIfEmpty(_ calendarIdentifier: String) throws -> Bool {
        let store = try readableStore()
        guard let calendar = store.calendar(withIdentifier: calendarIdentifier) else { return false }
        // EventKit reads at most four years at once: a calendar that holds anything, in any of the spans, is kept.
        for window in CalendarCopyEvents.searchWindows(calendar: Self.dayCalendar) {
            let predicate = store.predicateForEvents(withStart: window.start, end: window.end, calendars: [calendar])
            guard store.events(matching: predicate).isEmpty else { return false }
        }
        try store.removeCalendar(calendar, commit: true)
        return true
    }

    // MARK: Private

    private func madeEventStore() -> EKEventStore {
        if let eventStore { return eventStore }
        let store = EKEventStore()
        eventStore = store
        return store
    }

    private func readableStore() throws -> EKEventStore {
        guard access().canRead else { throw CalendarCopyStoreError.accessRefused }
        return madeEventStore()
    }

    /// The source of the calendar new events go to (iCloud on most devices, where a calendar of the local source would
    /// be hidden), else the device's own.
    private static func preferredSource(in store: EKEventStore) -> EKSource? {
        if let source = store.defaultCalendarForNewEvents?.source { return source }
        return store.sources.first { source in source.sourceType == .local }
    }

    /// Days are counted in the device's time zone, as the calendar view counts them.
    private static var dayCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    private static func timing(of event: EKEvent, in calendar: Calendar) -> CopiedEventTiming {
        guard event.isAllDay else { return .timed(start: event.startDate, end: event.endDate) }
        let firstDay = CalendarDay(event.startDate, in: calendar)
        // EventKit ends an all-day event at the last moment of its last day.
        let lastDay = max(firstDay, CalendarDay(event.endDate.addingTimeInterval(-1), in: calendar))
        return .allDay(firstDay: firstDay, lastDay: lastDay)
    }

    private static func write(_ copied: CopiedEvent, into event: EKEvent) {
        event.title = copied.title
        event.notes = copied.notes
        event.url = URL(string: copied.link)
        switch copied.timing {
        case .allDay(let firstDay, let lastDay):
            let calendar = dayCalendar
            event.isAllDay = true
            event.startDate = firstDay.startDate(in: calendar) ?? .now
            // The last day's start, which EventKit stretches to the end of that day.
            event.endDate = lastDay.startDate(in: calendar) ?? event.startDate
        case .timed(let start, let end):
            event.isAllDay = false
            event.startDate = start
            event.endDate = end
        }
    }
}
