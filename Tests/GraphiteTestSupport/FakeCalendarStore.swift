/**
 * File: FakeCalendarStore.swift
 * -----------------------------
 * Layer: Tests
 * Description: Calendars and Reminders lists that answer as a test sets them up and count what was asked of them, so
 *              no test asks for access to the real calendars or reminders, or reads or writes them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

import Foundation
import GraphiteCore
import GraphiteApple

/// Calendars and Reminders lists in memory, which answer as a test sets them up. It keeps the store's contract: reading
/// without access throws, asking shows the "question" only when never answered, and a change is announced to every
/// stream of `changes()`.
@MainActor
public final class FakeCalendarStore: CalendarStore {
    public private(set) var currentAccess: [CalendarStoreEntity: CalendarAccess]
    /// What the person answers when asked, for each entity.
    public var answers: [CalendarStoreEntity: CalendarAccess]
    public var events: [CalendarEvent]
    public var eventCalendars: [CalendarList]
    public var reminderLists: [CalendarList]
    public private(set) var storedReminders: [ReminderItem]
    public private(set) var accessReadCount = 0
    public private(set) var accessRequestCount = 0
    public private(set) var readCount = 0
    public private(set) var savedChanges: [ReminderChange] = []
    private var changeContinuations: [AsyncStream<Void>.Continuation] = []
    private var nextReminderNumber = 1

    public init(access: CalendarAccess = .notAsked, answer: CalendarAccess = .granted, events: [CalendarEvent] = [], reminders: [ReminderItem] = [],
                eventCalendars: [CalendarList] = [], reminderLists: [CalendarList] = [CalendarList(id: "inbox", title: "Inbox")]) {
        currentAccess = [.events: access, .reminders: access]
        answers = [.events: answer, .reminders: answer]
        self.events = events
        storedReminders = reminders
        self.eventCalendars = eventCalendars
        self.reminderLists = reminderLists
    }

    /// Whether anything was asked of the store at all.
    public var wasAskedAnything: Bool { accessReadCount + accessRequestCount + readCount + savedChanges.count > 0 }
    /// How many streams of changes are being listened to.
    public var listenerCount: Int { changeContinuations.count }

    public func access(to entity: CalendarStoreEntity) -> CalendarAccess {
        accessReadCount += 1
        return currentAccess[entity] ?? .notAsked
    }

    public func requestAccess(to entity: CalendarStoreEntity) async -> CalendarAccess {
        accessRequestCount += 1
        if currentAccess[entity] == .notAsked { currentAccess[entity] = answers[entity] ?? .refused }
        return currentAccess[entity] ?? .notAsked
    }

    /// Changes the access as the person would in Settings.
    public func setAccess(_ access: CalendarAccess, for entity: CalendarStoreEntity) {
        currentAccess[entity] = access
    }

    public func lists(of entity: CalendarStoreEntity) throws -> [CalendarList] {
        try checkReadable(entity)
        switch entity {
        case .events: return eventCalendars
        case .reminders: return reminderLists
        }
    }

    public func events(from start: Date, to end: Date) async throws -> [CalendarEvent] {
        try checkReadable(.events)
        return events.filter { event in event.startDate < end && (event.endDate > start || event.startDate >= start) }
    }

    public func reminders() async throws -> [ReminderItem] {
        try checkReadable(.reminders)
        return storedReminders
    }

    @discardableResult public func save(_ change: ReminderChange) async throws -> ReminderItem {
        try checkReadable(.reminders)
        savedChanges.append(change)
        switch change {
        case .add(let draft):
            let listTitle = draft.listTitle ?? reminderLists.first?.title ?? ""
            guard reminderLists.contains(where: { list in list.title == listTitle }) else { throw CalendarStoreError.listNotFound(listTitle) }
            let reminder = ReminderItem(id: "fake-reminder-\(nextReminderNumber)", listTitle: listTitle, title: draft.title, dueDay: draft.dueDay, link: draft.link)
            nextReminderNumber += 1
            storedReminders.append(reminder)
            return reminder
        case .setCompleted(let identifier, let isCompleted):
            guard let index = storedReminders.firstIndex(where: { reminder in reminder.id == identifier }) else { throw CalendarStoreError.reminderNotFound }
            storedReminders[index].isCompleted = isCompleted
            return storedReminders[index]
        }
    }

    /// Ticks or unticks a reminder as the person would in Reminders, and announces the change.
    public func completeInReminders(_ identifier: String, isCompleted: Bool = true) {
        guard let index = storedReminders.firstIndex(where: { reminder in reminder.id == identifier }) else { return }
        storedReminders[index].isCompleted = isCompleted
        announceChange()
    }

    public func announceChange() {
        for continuation in changeContinuations { continuation.yield() }
    }

    public func changes() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        changeContinuations.append(continuation)
        return stream
    }

    private func checkReadable(_ entity: CalendarStoreEntity) throws {
        readCount += 1
        guard currentAccess[entity]?.canRead == true else { throw CalendarStoreError.accessRefused(entity) }
    }
}
