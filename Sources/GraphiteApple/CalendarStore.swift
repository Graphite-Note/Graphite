/**
 * File: CalendarStore.swift
 * -------------------------
 * Layer: Apple
 * Description: Apple's Calendar and Reminders through EventKit: whether the person lets Graphite read them, the
 *              question asked at a feature's first use, a day's events, the reminders of the lists, and the reminders
 *              Graphite adds for tasks.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

import EventKit
import GraphiteCore

/// What Graphite reads from: the person's calendars, or their Reminders lists. Each is allowed or refused on its own.
public enum CalendarStoreEntity: Sendable, CaseIterable {
    case events, reminders
}

/// Whether the person lets Graphite read their calendars or reminders.
public enum CalendarAccess: Equatable, Sendable {
    /// Never asked: the first use of a feature asks.
    case notAsked
    case granted
    /// Graphite may add events but not read them; for what Graphite reads, the same as refused.
    case writeOnly
    /// The person said no, or turned it off in Settings › Privacy & Security.
    case refused
    /// The device does not allow it, as with Screen Time or a device profile.
    case restricted

    /// Whether Graphite can read what the person keeps there.
    public var canRead: Bool { self == .granted }
}

/// A change Graphite makes in Reminders. It adds reminders for tasks and ticks or unticks the reminders it added; it
/// never deletes a reminder.
public enum ReminderChange: Equatable, Sendable {
    case add(ReminderDraft)
    case setCompleted(reminderIdentifier: String, isCompleted: Bool)
}

/// Apple's Calendar and Reminders, for the Calendar core plugin. A protocol because the tests answer for it: no test
/// asks the person for access, and none reads or writes the calendars or reminders of the machine it runs on.
///
/// Reading `access` never shows a question; only `requestAccess` asks, and only when the person has never answered.
/// Reading events or reminders without access throws `CalendarStoreError.accessRefused`.
@MainActor
public protocol CalendarStore: AnyObject {
    func access(to entity: CalendarStoreEntity) -> CalendarAccess
    func requestAccess(to entity: CalendarStoreEntity) async -> CalendarAccess
    /// The person's calendars of events, or their Reminders lists, by title.
    func lists(of entity: CalendarStoreEntity) throws -> [CalendarList]
    /// The events that overlap the time from `start` to `end`, from every calendar.
    func events(from start: Date, to end: Date) async throws -> [CalendarEvent]
    /// The reminders of every list, open and completed.
    func reminders() async throws -> [ReminderItem]
    /// Adds a reminder or ticks one; the reminder as Reminders keeps it afterwards.
    @discardableResult func save(_ change: ReminderChange) async throws -> ReminderItem
    /// Hears that Calendar or Reminders changed, in Graphite or another app, until the stream is ended.
    func changes() -> AsyncStream<Void>
}

public enum CalendarStoreError: LocalizedError, Equatable {
    case accessRefused(CalendarStoreEntity)
    case reminderNotFound
    case listNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .accessRefused(.events):
            "Graphite cannot read your calendars. Allow it in Settings › Privacy & Security › Calendars."
        case .accessRefused(.reminders):
            "Graphite cannot read your reminders. Allow it in Settings › Privacy & Security › Reminders."
        case .reminderNotFound: "The reminder is no longer in Reminders."
        case .listNotFound(let title): "There is no Reminders list “\(title)”. Choose another in Settings › Calendar."
        }
    }
}

/// The system's Calendar and Reminders. The event store is made at the first question that needs it, so a launch that
/// uses no calendar feature makes none, and nothing listens for changes until `changes()` is asked.
@MainActor
public final class LiveCalendarStore: CalendarStore {
    private var eventStore: EKEventStore?

    public nonisolated init() {}

    public func access(to entity: CalendarStoreEntity) -> CalendarAccess {
        Self.access(of: EKEventStore.authorizationStatus(for: Self.entityType(entity)))
    }

    public func requestAccess(to entity: CalendarStoreEntity) async -> CalendarAccess {
        let currentAccess = access(to: entity)
        guard currentAccess == .notAsked else { return currentAccess }
        let store = madeEventStore()
        do {
            switch entity {
            case .events: _ = try await store.requestFullAccessToEvents()
            case .reminders: _ = try await store.requestFullAccessToReminders()
            }
        } catch {
            // The question could not be shown; the person is asked again next time.
            return .notAsked
        }
        return access(to: entity)
    }

    public func lists(of entity: CalendarStoreEntity) throws -> [CalendarList] {
        let store = try readableStore(for: entity)
        return store.calendars(for: Self.entityType(entity))
            .map { calendar in CalendarList(id: calendar.calendarIdentifier, title: calendar.title) }
            .sorted { first, second in first.title.localizedStandardCompare(second.title) == .orderedAscending }
    }

    public func events(from start: Date, to end: Date) async throws -> [CalendarEvent] {
        let store = try readableStore(for: .events)
        // A day or a month of events is read in milliseconds; EventKit gives its objects to the thread that asks.
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).map(Self.event(from:))
    }

    public func reminders() async throws -> [ReminderItem] {
        let store = try readableStore(for: .reminders)
        let predicate = store.predicateForReminders(in: nil)
        return await withCheckedContinuation { continuation in
            // EventKit answers on a thread of its own: the reminders are read into values there, so none of its objects
            // leaves that thread.
            store.fetchReminders(matching: predicate) { @Sendable reminders in
                continuation.resume(returning: (reminders ?? []).map(Self.reminder(from:)))
            }
        }
    }

    @discardableResult public func save(_ change: ReminderChange) async throws -> ReminderItem {
        let store = try readableStore(for: .reminders)
        let reminder: EKReminder
        switch change {
        case .add(let draft):
            reminder = EKReminder(eventStore: store)
            reminder.title = draft.title
            reminder.url = draft.link
            reminder.calendar = try list(titled: draft.listTitle, in: store)
            if let dueDay = draft.dueDay {
                reminder.dueDateComponents = DateComponents(calendar: Calendar(identifier: .gregorian), year: dueDay.year, month: dueDay.month, day: dueDay.day)
            }
        case .setCompleted(let reminderIdentifier, let isCompleted):
            guard let existing = store.calendarItem(withIdentifier: reminderIdentifier) as? EKReminder else { throw CalendarStoreError.reminderNotFound }
            reminder = existing
            reminder.isCompleted = isCompleted
        }
        try store.save(reminder, commit: true)
        return Self.reminder(from: reminder)
    }

    public func changes() -> AsyncStream<Void> {
        _ = madeEventStore()
        return AsyncStream { continuation in
            // Graphite makes one event store, so every change notice of the process is about it.
            let listening = Task { @MainActor in
                for await _ in NotificationCenter.default.notifications(named: .EKEventStoreChanged) { continuation.yield() }
                continuation.finish()
            }
            continuation.onTermination = { _ in listening.cancel() }
        }
    }

    // MARK: Private

    private func madeEventStore() -> EKEventStore {
        if let eventStore { return eventStore }
        let store = EKEventStore()
        eventStore = store
        return store
    }

    private func readableStore(for entity: CalendarStoreEntity) throws -> EKEventStore {
        guard access(to: entity).canRead else { throw CalendarStoreError.accessRefused(entity) }
        return madeEventStore()
    }

    private func list(titled title: String?, in store: EKEventStore) throws -> EKCalendar? {
        guard let title, !title.isEmpty else { return store.defaultCalendarForNewReminders() }
        guard let list = store.calendars(for: .reminder).first(where: { calendar in calendar.title == title }) else {
            throw CalendarStoreError.listNotFound(title)
        }
        return list
    }

    nonisolated static func event(from event: EKEvent) -> CalendarEvent {
        let attendees = ([event.organizer].compactMap { organizer in organizer } + (event.attendees ?? []))
            .map { participant in participant.name ?? participant.url.absoluteString.replacingOccurrences(of: "mailto:", with: "") }
        var uniqueAttendees: [String] = []
        for attendee in attendees where !attendee.isEmpty && !uniqueAttendees.contains(attendee) { uniqueAttendees.append(attendee) }
        let identifier = (event.eventIdentifier ?? event.calendarItemIdentifier) + "|" + String(event.startDate.timeIntervalSinceReferenceDate)
        return CalendarEvent(id: identifier, calendarTitle: event.calendar?.title ?? "", title: event.title ?? "", startDate: event.startDate,
                             endDate: event.endDate, isAllDay: event.isAllDay, location: event.location, attendees: uniqueAttendees)
    }

    nonisolated static func reminder(from reminder: EKReminder) -> ReminderItem {
        let dueDay = reminder.dueDateComponents.flatMap { components -> CalendarDay? in
            guard let year = components.year, let month = components.month, let day = components.day else { return nil }
            return CalendarDay(year: year, month: month, day: day)
        }
        return ReminderItem(id: reminder.calendarItemIdentifier, listTitle: reminder.calendar?.title ?? "", title: reminder.title ?? "",
                            dueDay: dueDay, isCompleted: reminder.isCompleted, link: reminder.url)
    }

    private nonisolated static func entityType(_ entity: CalendarStoreEntity) -> EKEntityType {
        switch entity {
        case .events: .event
        case .reminders: .reminder
        }
    }

    nonisolated static func access(of status: EKAuthorizationStatus) -> CalendarAccess {
        switch status {
        case .notDetermined: .notAsked
        case .fullAccess: .granted
        case .writeOnly: .writeOnly
        case .denied: .refused
        case .restricted: .restricted
        @unknown default: .refused
        }
    }
}
