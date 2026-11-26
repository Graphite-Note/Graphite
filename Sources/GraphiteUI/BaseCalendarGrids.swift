/**
 * File: BaseCalendarGrids.swift
 * -----------------------------
 * Layer: UI
 * Description: The grids of a base's calendar view: a month with titled bars and a week of day columns for the iPad
 *              and the Mac, and a month with marks over the chosen day's list and a week as a list for the iPhone.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import SwiftUI
import GraphiteCore

/// The weekday names over a grid's columns, from the calendar's first weekday.
private struct BaseCalendarWeekdayHeader: View {
    let days: [CalendarDay]
    let calendar: Calendar

    var body: some View {
        HStack(spacing: 0) {
            ForEach(days, id: \.self) { day in
                Text(day.startDate(in: calendar)?.formatted(.dateTime.weekday(.abbreviated)) ?? "")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 6)
        .accessibilityHidden(true)
    }
}

/// A day's number, circled in the accent color on today.
private struct BaseCalendarDayNumber: View {
    let day: CalendarDay
    let isToday: Bool
    let isInShownMonth: Bool

    var body: some View {
        Text("\(day.day)")
            .font(.callout.weight(isToday ? .bold : .regular))
            .monospacedDigit()
            .foregroundStyle(isToday ? AnyShapeStyle(Color.white) : (isInShownMonth ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary)))
            .frame(minWidth: 24, minHeight: 22)
            .background { if isToday { Capsule().fill(.tint) } }
    }
}

// MARK: The month with titled bars

/// A month for a wide view: each week a row of days, each entry a titled bar over its days, in lanes. A day with more
/// entries than lanes says how many more, which opens its week.
struct BaseCalendarMonthGrid: View {
    static let laneCount = 3
    static let laneHeight: CGFloat = 20
    static let dayNumberHeight: CGFloat = 26
    static let moreHeight: CGFloat = 18
    static var weekHeight: CGFloat { dayNumberHeight + CGFloat(laneCount) * laneHeight + moreHeight }

    let month: CalendarMonth
    let entries: [BaseCalendarEntry]
    let context: BaseCalendarContext
    let showWeek: (CalendarDay) -> Void

    var body: some View {
        let weeks = BaseCalendarLayout.weeks(of: month, entries: entries, calendar: context.calendar)
        VStack(spacing: 0) {
            BaseCalendarWeekdayHeader(days: weeks.first?.days ?? [], calendar: context.calendar)
            ForEach(weeks, id: \.days) { week in
                Divider()
                weekRow(week)
            }
        }
    }

    private func weekRow(_ week: BaseCalendarWeek) -> some View {
        GeometryReader { geometry in
            let columnWidth = geometry.size.width / CGFloat(max(week.days.count, 1))
            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    ForEach(Array(week.days.enumerated()), id: \.element) { column, day in dayCell(day, column: column, week: week) }
                }
                ForEach(week.placements.filter { placement in placement.lane < Self.laneCount }, id: \.entry.id) { placement in
                    bar(placement, in: week, columnWidth: columnWidth)
                }
            }
        }
        .frame(height: Self.weekHeight)
    }

    private func dayCell(_ day: CalendarDay, column: Int, week: BaseCalendarWeek) -> some View {
        let hiddenCount = week.hiddenEntryCount(inColumn: column, laneCount: Self.laneCount)
        let dayEntries = week.entries(on: day)
        return VStack(alignment: .leading, spacing: 0) {
            BaseCalendarDayNumber(day: day, isToday: day == context.today, isInShownMonth: month.contains(day))
                .frame(height: Self.dayNumberHeight)
                .padding(.leading, 4)
            Spacer(minLength: 0)
            if hiddenCount > 0 {
                Button("+\(hiddenCount) more") { showWeek(day) }
                    .buttonStyle(.plain)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(height: Self.moreHeight)
                    .padding(.leading, 6)
                    .help("Show this week")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(month.contains(day) ? Color.clear : Color.secondary.opacity(0.06))
        .overlay(alignment: .trailing) { if column < 6 { Rectangle().fill(Color.secondary.opacity(0.2)).frame(width: 0.5) } }
        .modifier(BaseCalendarDropTarget(day: day, context: context))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(BaseCalendarAccessibility.dayLabel(day, entryCount: dayEntries.count, calendar: context.calendar))
    }

    /// One bar per entry and week, with a part per day that carries that day when dragged.
    private func bar(_ placement: BaseCalendarPlacement, in week: BaseCalendarWeek, columnWidth: CGFloat) -> some View {
        let columns = placement.firstColumn...placement.lastColumn
        let width = CGFloat(columns.count) * columnWidth - 4
        let isTimed = placement.entry.startTime != nil && placement.entry.firstDay == placement.entry.lastDay
        return ZStack(alignment: .leading) {
            // A tint over the page's own color, so the lines between the days do not show through a bar.
            if !isTimed { RoundedRectangle(cornerRadius: 4).fill(.background).overlay(RoundedRectangle(cornerRadius: 4).fill(Color.accentColor.opacity(0.2))) }
            HStack(spacing: 4) {
                if isTimed { Circle().fill(.tint).frame(width: 6, height: 6) }
                if isTimed, let time = placement.entry.startTime {
                    Text(time, format: .dateTime.hour().minute()).foregroundStyle(.secondary).monospacedDigit()
                }
                Text(context.title(of: placement.entry)).lineLimit(1)
            }
            .font(.caption)
            .padding(.horizontal, 5)
            HStack(spacing: 0) {
                ForEach(Array(columns), id: \.self) { column in
                    Color.clear.frame(width: columnWidth)
                        .modifier(BaseCalendarEntryInteraction(entry: placement.entry, day: week.days[column], context: context,
                                                               isAccessibilityElement: column == placement.firstColumn))
                        .modifier(BaseCalendarDropTarget(day: week.days[column], context: context, drawsOutline: false))
                }
            }
        }
        .frame(width: max(width, 0), height: Self.laneHeight - 2, alignment: .leading)
        .clipped()
        .offset(x: CGFloat(placement.firstColumn) * columnWidth + 2, y: Self.dayNumberHeight + CGFloat(placement.lane) * Self.laneHeight)
    }
}

// MARK: The week of day columns

/// A week for a wide view: seven columns, each listing its day's entries in order, timed ones with their time.
struct BaseCalendarWeekColumns: View {
    static let minimumHeight: CGFloat = 320

    let week: BaseCalendarWeek
    let context: BaseCalendarContext

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(week.days.enumerated()), id: \.element) { column, day in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(day.startDate(in: context.calendar)?.formatted(.dateTime.weekday(.abbreviated)) ?? "")
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        BaseCalendarDayNumber(day: day, isToday: day == context.today, isInShownMonth: true)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(BaseCalendarAccessibility.dayLabel(day, entryCount: week.entries(on: day).count, calendar: context.calendar))
                    ForEach(week.entries(on: day)) { entry in
                        BaseCalendarEntryCard(entry: entry, day: day, context: context)
                    }
                    Spacer(minLength: 0)
                }
                .padding(6)
                .frame(maxWidth: .infinity, minHeight: Self.minimumHeight, alignment: .topLeading)
                .overlay(alignment: .trailing) { if column < 6 { Rectangle().fill(Color.secondary.opacity(0.2)).frame(width: 0.5) } }
                .modifier(BaseCalendarDropTarget(day: day, context: context))
            }
        }
    }
}

/// An entry in a list or a week's column: its title, and its time, or its days when it spans several.
private struct BaseCalendarEntryCard: View {
    let entry: BaseCalendarEntry
    let day: CalendarDay
    let context: BaseCalendarContext

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(context.title(of: entry)).font(.callout).lineLimit(2)
            if let detail = detailText { Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
        .modifier(BaseCalendarEntryInteraction(entry: entry, day: day, context: context))
    }

    private var detailText: String? {
        if entry.lastDay != entry.firstDay { return context.dateText(of: entry) }
        return entry.startTime?.formatted(.dateTime.hour().minute())
    }
}

// MARK: The phone's month and week

/// A month for a narrow view: each day marked with a dot per entry (three at most), and the chosen day's entries
/// listed under the grid. An entry dragged from the list onto a day moves there.
struct BaseCalendarCompactMonth: View {
    static let maximumMarks = 3

    let month: CalendarMonth
    let entries: [BaseCalendarEntry]
    let chosenDay: CalendarDay
    let context: BaseCalendarContext
    let choose: (CalendarDay) -> Void

    var body: some View {
        let weeks = BaseCalendarLayout.weeks(of: month, entries: entries, calendar: context.calendar)
        VStack(spacing: 0) {
            BaseCalendarWeekdayHeader(days: weeks.first?.days ?? [], calendar: context.calendar)
            ForEach(weeks, id: \.days) { week in
                HStack(spacing: 0) {
                    ForEach(week.days, id: \.self) { day in dayCell(day, entryCount: week.entries(on: day).count) }
                }
            }
            Divider().padding(.top, 6)
            chosenDayList(entries.filter { entry in entry.covers(chosenDay) })
        }
    }

    private func dayCell(_ day: CalendarDay, entryCount: Int) -> some View {
        let isChosen = day == chosenDay
        return VStack(spacing: 3) {
            BaseCalendarDayNumber(day: day, isToday: day == context.today, isInShownMonth: month.contains(day))
            HStack(spacing: 2) {
                ForEach(0..<min(entryCount, Self.maximumMarks), id: \.self) { _ in Circle().fill(.tint).frame(width: 5, height: 5) }
            }
            .frame(height: 5)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .background { if isChosen { RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.15)) } }
        .contentShape(Rectangle())
        .onTapGesture { choose(day) }
        .modifier(BaseCalendarDropTarget(day: day, context: context))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(BaseCalendarAccessibility.dayLabel(day, entryCount: entryCount, calendar: context.calendar))
        .accessibilityAddTraits(isChosen ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { choose(day) }
    }

    @ViewBuilder private func chosenDayList(_ dayEntries: [BaseCalendarEntry]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(chosenDay.startDate(in: context.calendar)?.formatted(.dateTime.weekday(.wide).month(.wide).day()) ?? chosenDay.isoText)
                .font(.subheadline.weight(.semibold))
            if dayEntries.isEmpty {
                Text("Nothing on this day").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(dayEntries) { entry in BaseCalendarEntryCard(entry: entry, day: chosenDay, context: context) }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A week for a narrow view: its seven days one under the other, each with its entries. A day takes dropped entries.
struct BaseCalendarWeekList: View {
    let week: BaseCalendarWeek
    let context: BaseCalendarContext

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(week.days, id: \.self) { day in
                let dayEntries = week.entries(on: day)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        BaseCalendarDayNumber(day: day, isToday: day == context.today, isInShownMonth: true)
                        Text(day.startDate(in: context.calendar)?.formatted(.dateTime.weekday(.wide)) ?? "")
                            .font(.subheadline.weight(.semibold))
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(BaseCalendarAccessibility.dayLabel(day, entryCount: dayEntries.count, calendar: context.calendar))
                    ForEach(dayEntries) { entry in BaseCalendarEntryCard(entry: entry, day: day, context: context) }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .modifier(BaseCalendarDropTarget(day: day, context: context))
                Divider()
            }
        }
    }
}

/// What VoiceOver reads for a day.
enum BaseCalendarAccessibility {
    static func dayLabel(_ day: CalendarDay, entryCount: Int, calendar: Calendar) -> String {
        let dateText = day.startDate(in: calendar)?.formatted(.dateTime.weekday(.wide).month(.wide).day()) ?? day.isoText
        switch entryCount {
        case 0: return dateText
        case 1: return dateText + ", 1 note"
        default: return dateText + ", \(entryCount) notes"
        }
    }
}
