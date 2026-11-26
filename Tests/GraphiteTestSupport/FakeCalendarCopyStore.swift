/**
 * File: FakeCalendarCopyStore.swift
 * ---------------------------------
 * Layer: Tests
 * Description: A "Graphite" calendar in memory that answers for EventKit as Calendar Copy uses it, so no test asks for
 *              access to the real calendars or writes them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import Foundation
import GraphiteCore
import GraphiteApple

/// A calendar store that answers for EventKit with one "Graphite" calendar in memory.
public actor FakeCalendarCopyStore: CalendarCopyStore {
    public static let calendarIdentifier = "fake-graphite-calendar"
    private var currentAccess: CalendarAccess
    private let answer: CalendarAccess
    public private(set) var questionCount = 0
    private var calendarExists = false
    private var events: [String: CalendarEventCopy] = [:]
    private var nextIdentifier = 0

    public init(access: CalendarAccess, answer: CalendarAccess = .granted) {
        currentAccess = access
        self.answer = answer
    }

    public func access() -> CalendarAccess { currentAccess }

    public func requestAccess() -> CalendarAccess {
        guard currentAccess == .notAsked else { return currentAccess }
        questionCount += 1
        currentAccess = answer
        return currentAccess
    }

    public func calendar(knownIdentifier: String?, title: String) throws -> String {
        guard currentAccess.canRead else { throw CalendarCopyStoreError.accessRefused }
        calendarExists = true
        return Self.calendarIdentifier
    }

    public func events(inCalendar calendarIdentifier: String, during window: DateInterval) -> [CalendarEventCopy] {
        guard calendarExists, calendarIdentifier == Self.calendarIdentifier else { return [] }
        return events.values.filter { event in Self.meets(event, window) }.sorted { first, second in first.identifier < second.identifier }
    }

    public func apply(_ plan: CalendarCopyPlan, inCalendar calendarIdentifier: String) -> CalendarCopyReport {
        var report = CalendarCopyReport()
        for removal in plan.removals where events.removeValue(forKey: removal) != nil { report.removedCount += 1 }
        for change in plan.changes where events[change.identifier] != nil {
            events[change.identifier] = copy(change.event, identifier: change.identifier)
            report.changedCount += 1
        }
        for addition in plan.additions {
            nextIdentifier += 1
            events["event-\(nextIdentifier)"] = copy(addition, identifier: "event-\(nextIdentifier)")
            report.addedCount += 1
        }
        return report
    }

    public func removeCalendarIfEmpty(_ calendarIdentifier: String) -> Bool {
        guard calendarExists, events.isEmpty else { return false }
        calendarExists = false
        return true
    }

    // MARK: What the tests do in "Calendar"

    public func addPersonalEvent(title: String) {
        nextIdentifier += 1
        let today = CalendarDay(.now, in: BaseDateFormatting.displayCalendar)
        events["personal-\(nextIdentifier)"] = CalendarEventCopy(identifier: "personal-\(nextIdentifier)", link: nil, title: title,
                                                                 timing: .allDay(firstDay: today, lastDay: today), notes: "")
    }

    public func removePersonalEvents() { events = events.filter { _, event in event.link != nil } }

    public func editTitle(of title: String, to newTitle: String) {
        guard let event = events.values.first(where: { event in event.title == title }) else { return }
        events[event.identifier] = CalendarEventCopy(identifier: event.identifier, link: event.link, title: newTitle, timing: event.timing, notes: event.notes)
    }

    public func graphiteEvents() -> [CalendarEventCopy] { events.values.filter { event in event.link != nil } }
    public func personalEventTitles() -> [String] { events.values.filter { event in event.link == nil }.map(\.title) }

    private func copy(_ event: CopiedEvent, identifier: String) -> CalendarEventCopy {
        CalendarEventCopy(identifier: identifier, link: event.link, title: event.title, timing: event.timing, notes: event.notes)
    }

    private static func meets(_ event: CalendarEventCopy, _ window: DateInterval) -> Bool {
        let calendar = BaseDateFormatting.displayCalendar
        switch event.timing {
        case .allDay(let firstDay, let lastDay):
            guard let start = firstDay.startDate(in: calendar), let end = lastDay.adding(days: 1, in: calendar).startDate(in: calendar) else { return false }
            return start < window.end && end > window.start
        case .timed(let start, let end):
            return start < window.end && end > window.start
        }
    }
}
