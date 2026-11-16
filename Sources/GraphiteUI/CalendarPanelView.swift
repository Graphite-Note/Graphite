/**
 * File: CalendarPanelView.swift
 * -----------------------------
 * Layer: UI
 * Description: The sidebar's calendar panel, as Obsidian's Calendar plugin shows it: a month whose days open their
 *              daily notes and are marked when they have one, and under it the chosen day's events from Calendar.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

import SwiftUI
import GraphiteCore
import GraphiteApple

/// The sidebar's calendar panel: rows of the sidebar's list, so it scrolls and looks as the other panels do. Choosing a
/// day opens its daily note; a dot marks the days that have one. The chosen day's events follow once the person lets
/// Graphite read their calendars, which is asked only when they choose to show events.
struct CalendarPanel: View {
    let model: CalendarPanelModel
    let actions: CalendarPanelActions
    /// Changes when files of the vault are added, moved or removed, so the marks are read again.
    let filesVersion: String
    @Environment(\.accent) private var accent

    private var calendar: Calendar { .autoupdatingCurrent }
    private var today: CalendarDay { CalendarDay(.now, in: calendar) }

    var body: some View {
        Section {
            // The loads hang on one row: inside a list, a section's modifiers apply to each of its rows.
            monthHeader
                .task(id: filesVersion) { await model.loadDaysWithNotes(actions: actions) }
                .task { await model.loadEvents(actions: actions) }
            CalendarMonthGrid(month: model.shownMonth, calendar: calendar, today: today, selectedDay: model.selectedDay,
                              daysWithNotes: model.daysWithNotes, accent: accent) { day in
                Task { await model.choose(day, actions: actions) }
            }
            .listRowSeparator(.hidden)
            if !actions.opensDailyNotes {
                Text("Turn on Daily Notes in Settings › Core Plugins to open a note for each day.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        Section(dayTitle) {
            eventRows
        }
    }

    private var monthHeader: some View {
        HStack(spacing: 4) {
            Text(model.shownMonth.title(in: calendar))
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 4)
            Button("Today") { Task { await model.showToday(today, actions: actions) } }
                .buttonStyle(.borderless)
                .disabled(model.shownMonth == CalendarMonth(containing: today) && model.selectedDay == today)
            Button("Previous Month", systemImage: "chevron.backward") { model.showMonth(offsetBy: -1) }
                .labelStyle(.iconOnly).buttonStyle(.borderless)
            Button("Next Month", systemImage: "chevron.forward") { model.showMonth(offsetBy: 1) }
                .labelStyle(.iconOnly).buttonStyle(.borderless)
        }
        .tint(accent)
        .listRowSeparator(.hidden)
    }

    /// "Thursday, 12 November", in the person's language.
    private var dayTitle: String {
        guard let date = model.selectedDay.startDate(in: calendar) else { return model.selectedDay.isoText }
        return date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    @ViewBuilder private var eventRows: some View {
        switch model.events {
        case .notAsked:
            Button("Show Events from Calendar", systemImage: "calendar.badge.clock") { Task { await model.allowEvents(actions: actions) } }
                .tint(accent)
            Text("Graphite asks once to read your calendars. Events stay on this device, and go into a note only when you ask.")
                .font(.footnote).foregroundStyle(.secondary)
        case .unavailable(let access):
            Text(access == .restricted
                 ? "Calendars cannot be read on this device."
                 : "Graphite cannot read your calendars. Allow it in Settings › Privacy & Security › Calendars.")
                .font(.footnote).foregroundStyle(.secondary)
        case .loading:
            ProgressView().frame(maxWidth: .infinity)
        case .loaded(let events) where events.isEmpty:
            Text("No events").foregroundStyle(.secondary)
        case .loaded(let events):
            ForEach(events) { event in
                CalendarEventRow(event: event, day: model.selectedDay, calendar: calendar) { Task { await actions.openEventNote(event) } }
            }
        case .failed(let reason):
            Text(reason).font(.footnote).foregroundStyle(.secondary)
        }
    }
}

/// The month's days in rows of weeks, under the weekdays' names.
struct CalendarMonthGrid: View {
    let month: CalendarMonth
    let calendar: Calendar
    let today: CalendarDay
    let selectedDay: CalendarDay
    let daysWithNotes: Set<CalendarDay>
    let accent: Color
    let choose: (CalendarDay) -> Void

    var body: some View {
        Grid(horizontalSpacing: 0, verticalSpacing: 2) {
            GridRow {
                ForEach(Array(month.weekdaySymbols(in: calendar).enumerated()), id: \.offset) { _, symbol in
                    Text(symbol).font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                }
            }
            ForEach(month.weeks(in: calendar), id: \.first) { week in
                GridRow {
                    ForEach(week, id: \.self) { day in dayButton(day) }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func dayButton(_ day: CalendarDay) -> some View {
        let isSelected = day == selectedDay
        let isToday = day == today
        let hasNote = daysWithNotes.contains(day)
        return Button { choose(day) } label: {
            VStack(spacing: 1) {
                Text("\(day.day)")
                    .font(.callout.monospacedDigit().weight(isToday ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.white : (isToday ? accent : (month.contains(day) ? Color.primary : Color.secondary)))
                    .frame(width: CalendarMonthGrid.dayDiameter, height: CalendarMonthGrid.dayDiameter)
                    .background { if isSelected { Circle().fill(accent) } }
                Circle().fill(hasNote ? accent : Color.clear).frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity, minHeight: CalendarMonthGrid.dayRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(of: day, isToday: isToday, hasNote: hasNote))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func accessibilityLabel(of day: CalendarDay, isToday: Bool, hasNote: Bool) -> String {
        let name = day.startDate(in: calendar).map { date in date.formatted(.dateTime.weekday(.wide).day().month(.wide)) } ?? day.isoText
        return [isToday ? "Today" : nil, name, hasNote ? "daily note" : nil].compactMap { part in part }.joined(separator: ", ")
    }

    /// A finger's width for each day, which keeps seven columns within a phone's or a narrow sidebar's width.
    static let dayDiameter: CGFloat = 28
    static let dayRowHeight: CGFloat = 36
}

/// One event of the chosen day: its time, title and place. Choosing it opens its note, made the first time.
struct CalendarEventRow: View {
    let event: CalendarEvent
    let day: CalendarDay
    let calendar: Calendar
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 2) {
                Text(event.displayTitle).lineLimit(2)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the event's note, made the first time")
        .contextMenu {
            Button("Open Event Note", systemImage: "doc.text") { open() }
        }
    }

    private var detail: String {
        var parts: [String] = []
        parts.append(CalendarEventList.timeText(of: event, on: day, calendar: calendar) { date in date.formatted(date: .omitted, time: .shortened) })
        if let location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines), !location.isEmpty {
            parts.append(location.components(separatedBy: .newlines).joined(separator: ", "))
        }
        if !event.calendarTitle.isEmpty { parts.append(event.calendarTitle) }
        return parts.joined(separator: " · ")
    }
}
