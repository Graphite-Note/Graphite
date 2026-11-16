/**
 * File: CalendarPanelModel.swift
 * ------------------------------
 * Layer: UI
 * Description: What the sidebar's calendar panel shows: the month, the chosen day, the days that have a daily note,
 *              and the chosen day's events once the person lets Graphite read their calendars.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

import Foundation
import Observation
import GraphiteCore
import GraphiteApple

/// What the calendar panel asks of the open vault and of Calendar.
struct CalendarPanelActions {
    let dailyNoteDays: @MainActor () async -> Set<CalendarDay>
    /// Calendar access, asking the person when they never answered and the argument is true.
    let eventAccess: @MainActor (_ asking: Bool) async -> CalendarAccess
    let events: @MainActor (CalendarDay) async throws -> [CalendarEvent]
    let openDailyNote: @MainActor (CalendarDay) async -> Void
    let openEventNote: @MainActor (CalendarEvent) async -> Void
    /// Whether choosing a day opens its daily note: the Daily notes core plugin is on.
    let opensDailyNotes: Bool
}

/// The chosen day's events, as far as Graphite may read them.
enum CalendarPanelEvents: Equatable {
    /// The person was never asked; the panel offers to show events, which asks.
    case notAsked
    /// Graphite may not read the calendars; the panel says where to allow it.
    case unavailable(CalendarAccess)
    case loading
    case loaded([CalendarEvent])
    case failed(String)
}

/// What the sidebar's calendar panel shows. It lives as long as the sidebar, so the month and the chosen day stay as
/// they were when the person comes back to the panel.
@MainActor @Observable
final class CalendarPanelModel {
    private(set) var shownMonth: CalendarMonth
    private(set) var selectedDay: CalendarDay
    private(set) var daysWithNotes: Set<CalendarDay> = []
    private(set) var events = CalendarPanelEvents.notAsked

    init(today: CalendarDay) {
        shownMonth = CalendarMonth(containing: today)
        selectedDay = today
    }

    func showMonth(offsetBy offset: Int) {
        shownMonth = shownMonth.adding(months: offset)
    }

    /// Shows today's month and chooses today, then reads today's events.
    func showToday(_ today: CalendarDay, actions: CalendarPanelActions) async {
        shownMonth = CalendarMonth(containing: today)
        selectedDay = today
        await loadEvents(actions: actions)
    }

    /// Chooses `day`, opens its daily note (made from the template when missing) and reads its events. A day of the
    /// month before or after shows that month.
    func choose(_ day: CalendarDay, actions: CalendarPanelActions) async {
        selectedDay = day
        if !shownMonth.contains(day) { shownMonth = CalendarMonth(containing: day) }
        if actions.opensDailyNotes { await actions.openDailyNote(day) }
        await loadEvents(actions: actions)
    }

    func loadDaysWithNotes(actions: CalendarPanelActions) async {
        daysWithNotes = await actions.dailyNoteDays()
    }

    /// Reads the chosen day's events when Graphite may; never asks.
    func loadEvents(actions: CalendarPanelActions) async {
        await loadEvents(access: await actions.eventAccess(false), actions: actions)
    }

    /// Asks for calendar access, as the person chose to show events, then reads the chosen day's.
    func allowEvents(actions: CalendarPanelActions) async {
        await loadEvents(access: await actions.eventAccess(true), actions: actions)
    }

    private func loadEvents(access: CalendarAccess, actions: CalendarPanelActions) async {
        switch access {
        case .notAsked: events = .notAsked
        case .writeOnly, .refused, .restricted: events = .unavailable(access)
        case .granted:
            let day = selectedDay
            if case .loaded = events {} else { events = .loading }
            do {
                let dayEvents = try await actions.events(day)
                // A later choice of day replaced this one meanwhile.
                guard day == selectedDay else { return }
                events = .loaded(dayEvents)
            } catch is CancellationError {
            } catch {
                events = .failed(CalendarFailureWording.words(for: error, doing: .readingEvents))
            }
        }
    }
}
