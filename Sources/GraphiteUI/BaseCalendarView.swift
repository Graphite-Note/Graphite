/**
 * File: BaseCalendarView.swift
 * ----------------------------
 * Layer: UI
 * Description: The calendar view of a base: its row of month or week, arrows, Today and the Month and Week switch,
 *              and what every entry does when tapped, dragged, held or read by VoiceOver.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import SwiftUI
import GraphiteCore

/// Moving a calendar's entries to other days, provided by the base's container.
struct BaseCalendarMoves {
    /// Whether the entry of this file can move: its dates are note properties the base may write.
    let canMove: (VaultPath) -> Bool
    /// Shifts the entry's start and end by a number of days.
    let move: (VaultPath, Int) -> Void
}

/// Whether the calendar shows a month or a week.
enum BaseCalendarScope: String, CaseIterable {
    case month, week

    var title: String { self == .month ? "Month" : "Week" }
}

/// The text a dragged entry carries: the day of the entry under the finger or pointer and the note's path, so a drop
/// moves the entry by the days between them, from whichever day of a long entry it was picked up.
enum BaseCalendarDragPayload {
    private static let prefix = "graphite-calendar-entry:"

    static func text(path: VaultPath, grabbedDay: CalendarDay) -> String {
        prefix + grabbedDay.isoText + ":" + path.rawValue
    }

    /// Nil for any other text, such as text dragged in from another app.
    static func entry(from text: String) -> (path: VaultPath, grabbedDay: CalendarDay)? {
        guard text.hasPrefix(prefix) else { return nil }
        let rest = text.dropFirst(prefix.count)
        guard rest.count > 11, let day = CalendarDay(isoText: String(rest.prefix(10))), rest.dropFirst(10).first == ":",
              let path = try? VaultPath(String(rest.dropFirst(11))) else { return nil } // A path no vault can hold: not an entry.
        return (path, day)
    }
}

/// The calendar view of a base, with Calendar Bases' keys: each note placed from its `startDate` to its `endDate` on
/// a month or a week, opened by a tap, moved by dragging it to another day.
struct BaseCalendarView: View {
    /// Narrower views (a phone, a base inside a narrow note) draw the compact month and the week as a list.
    static let compactWidthThreshold: CGFloat = 600

    let result: BaseQueryResult
    let actions: BaseViewActions
    /// Where the Month or Week choice of this view is remembered.
    let layoutMemoryKey: String
    let moves: BaseCalendarMoves
    /// Opens the view editor; nil where the base cannot be edited from here.
    let editView: (() -> Void)?
    /// What the view shows until the person chooses Month or Week.
    var defaultScope = BaseCalendarScope.month
    @Environment(\.basesScrollVertically) private var scrollsVertically
    /// The Month or Week choice of each calendar view shown in this window, as JSON (`BaseCalendarScopeMemory`).
    @SceneStorage("GraphiteBaseCalendarScopes") private var storedScopes = ""
    /// The day the shown month or week holds; today until the person moves.
    @State private var shownDay: CalendarDay?
    /// The compact month's chosen day, whose entries are listed under it.
    @State private var chosenDay: CalendarDay?
    @State private var targetedDay: CalendarDay?
    @State private var availableWidth: CGFloat?

    private var options: BaseCalendarOptions { result.view.calendar }
    private var calendar: Calendar { BaseCalendarLayout.calendar(weekStartDay: options.weekStartDay) }
    private var today: CalendarDay { CalendarDay(.now, in: calendar) }
    private var isCompact: Bool { (availableWidth ?? .infinity) < Self.compactWidthThreshold }
    private var scope: BaseCalendarScope { BaseCalendarScopeMemory.scope(for: layoutMemoryKey, in: storedScopes) ?? defaultScope }

    var body: some View {
        Group {
            if options.startDateProperty == nil {
                ContentUnavailableView {
                    Label("Choose the Calendar's Dates", systemImage: BaseViewType.calendar.systemImage)
                } description: {
                    Text("A calendar places each note on the day of a date property. Choose it as the Start Date in Edit View.")
                } actions: {
                    if let editView { Button("Edit View…", action: editView) }
                }
            } else {
                calendarContent
            }
        }
        .onGeometryChange(for: CGFloat.self) { geometry in geometry.size.width } action: { width in availableWidth = width }
    }

    @ViewBuilder private var calendarContent: some View {
        let calendar = calendar
        let entries = BaseCalendarEntry.entries(of: result, calendar: calendar)
        let context = BaseCalendarContext(calendar: calendar, today: today, titles: Self.titles(of: result), actions: actions, moves: moves,
                                          targetedDay: targetedDay, setTargetedDay: { day in targetedDay = day },
                                          drop: { [moves] payloads, day in
                                              BaseCalendarDrop.move(payloads, onto: day, entries: entries, moves: moves, calendar: calendar)
                                          })
        let day = shownDay ?? today
        VStack(spacing: 0) {
            header(shownDay: day)
            Divider()
            if scrollsVertically {
                ScrollView(.vertical) { grid(day: day, entries: entries, context: context) }
            } else {
                grid(day: day, entries: entries, context: context)
            }
        }
    }

    @ViewBuilder private func grid(day: CalendarDay, entries: [BaseCalendarEntry], context: BaseCalendarContext) -> some View {
        switch (scope, isCompact) {
        case (.month, false):
            BaseCalendarMonthGrid(month: CalendarMonth(containing: day), entries: entries, context: context) { moreDay in
                setScope(.week)
                shownDay = moreDay
            }
        case (.month, true):
            let chosen = chosenDay.flatMap { chosen in CalendarMonth(containing: day).contains(chosen) ? chosen : nil }
                ?? (CalendarMonth(containing: day).contains(today) ? today : CalendarDay(year: day.year, month: day.month, day: 1))
            BaseCalendarCompactMonth(month: CalendarMonth(containing: day), entries: entries, chosenDay: chosen, context: context) { tappedDay in
                chosenDay = tappedDay
            }
        case (.week, false):
            BaseCalendarWeekColumns(week: BaseCalendarLayout.week(containing: day, entries: entries, calendar: context.calendar), context: context)
        case (.week, true):
            BaseCalendarWeekList(week: BaseCalendarLayout.week(containing: day, entries: entries, calendar: context.calendar), context: context)
        }
    }

    // MARK: The row above the grid

    private func header(shownDay day: CalendarDay) -> some View {
        HStack(spacing: isCompact ? 8 : 12) {
            Text(title(of: day))
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .layoutPriority(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Picker("Show", selection: Binding(get: { scope }, set: { newScope in setScope(newScope) })) {
                ForEach(BaseCalendarScope.allCases, id: \.self) { scope in Text(scope.title).tag(scope) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            ControlGroup {
                Button("Previous", systemImage: "chevron.left") { move(by: -1) }
                    .help(scope == .month ? "Previous month" : "Previous week")
                Button("Today") { shownDay = today }
                    .help("Show today")
                Button("Next", systemImage: "chevron.right") { move(by: 1) }
                    .help(scope == .month ? "Next month" : "Next week")
            }
            .fixedSize()
        }
        // A phone's row holds the month's short name beside smaller controls.
        .controlSize(isCompact ? .small : .regular)
        .padding(.horizontal, isCompact ? 12 : 16)
        .padding(.vertical, 8)
    }

    private func title(of day: CalendarDay) -> String {
        switch scope {
        case .month:
            guard isCompact, let first = CalendarDay(year: day.year, month: day.month, day: 1).startDate(in: calendar) else {
                return CalendarMonth(containing: day).title(in: calendar)
            }
            // A phone's row has room for "Nov 2026" beside the switch and the arrows, not for "November 2026".
            return first.formatted(.dateTime.month(.abbreviated).year())
        case .week:
            let days = BaseCalendarLayout.days(ofWeekContaining: day, calendar: calendar)
            guard let first = days.first?.startDate(in: calendar), let last = days.last?.startDate(in: calendar) else { return "" }
            let formatter = DateIntervalFormatter()
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.dateTemplate = isCompact ? "MMMd" : "MMMdyyyy"
            return formatter.string(from: first, to: last)
        }
    }

    private func move(by step: Int) {
        let day = shownDay ?? today
        switch scope {
        case .month:
            let month = CalendarMonth(containing: day).adding(months: step)
            shownDay = CalendarDay(year: month.year, month: month.month, day: 1)
        case .week:
            shownDay = day.adding(days: 7 * step, in: calendar)
        }
        chosenDay = nil
    }

    private func setScope(_ newScope: BaseCalendarScope) {
        storedScopes = BaseCalendarScopeMemory.remembering(newScope, for: layoutMemoryKey, in: storedScopes)
    }

    // MARK: Entries

    static func titles(of result: BaseQueryResult) -> [VaultPath: String] {
        Dictionary(result.rows.map { row in (row.path, BaseCalendarEntry.title(of: row, columns: result.columns)) }, uniquingKeysWith: { first, _ in first })
    }

}

/// What a drop on a day of the calendar does.
enum BaseCalendarDrop {
    /// Moves the entries dropped on `day` by the days between the day each was picked up on and this one. Anything else
    /// dropped there, an entry of another calendar or one that cannot move, moves nothing.
    /// - Returns: Whether an entry moved.
    static func move(_ payloads: [String], onto day: CalendarDay, entries: [BaseCalendarEntry], moves: BaseCalendarMoves, calendar: Calendar) -> Bool {
        var isMoved = false
        for payload in payloads {
            guard let dragged = BaseCalendarDragPayload.entry(from: payload), entries.contains(where: { entry in entry.path == dragged.path }),
                  moves.canMove(dragged.path) else { continue }
            let dayOffset = BaseCalendarRescheduling.dayOffset(from: dragged.grabbedDay, to: day, calendar: calendar)
            guard dayOffset != 0 else { continue }
            moves.move(dragged.path, dayOffset)
            isMoved = true
        }
        return isMoved
    }
}

/// What every part of the grid needs: the calendar, the entries' titles and what an entry does.
struct BaseCalendarContext {
    let calendar: Calendar
    let today: CalendarDay
    let titles: [VaultPath: String]
    let actions: BaseViewActions
    let moves: BaseCalendarMoves
    let targetedDay: CalendarDay?
    let setTargetedDay: (CalendarDay?) -> Void
    let drop: ([String], CalendarDay) -> Bool

    func title(of entry: BaseCalendarEntry) -> String { titles[entry.path] ?? BaseValue.file(entry.path).displayText }

    /// "Dec 3", "Dec 3 – 5", or "Dec 3, 14:00", for VoiceOver and the lists.
    func dateText(of entry: BaseCalendarEntry) -> String {
        guard let first = entry.firstDay.startDate(in: calendar) else { return entry.firstDay.isoText }
        if entry.lastDay != entry.firstDay, let last = entry.lastDay.startDate(in: calendar) {
            let formatter = DateIntervalFormatter()
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.dateTemplate = "MMMd"
            return formatter.string(from: first, to: last)
        }
        let dayText = first.formatted(.dateTime.month(.abbreviated).day())
        guard let time = entry.startTime else { return dayText }
        return dayText + ", " + time.formatted(.dateTime.hour().minute())
    }
}

/// Remembers each calendar view's Month or Week choice in the window's scene storage, as a small JSON object.
enum BaseCalendarScopeMemory {
    /// The most views remembered; the oldest choices go first.
    static let maximumRememberedViews = 100

    /// The scope chosen for the view, nil when none was.
    static func scope(for key: String, in storedText: String) -> BaseCalendarScope? {
        entries(in: storedText).last { entry in entry.key == key }.flatMap { entry in BaseCalendarScope(rawValue: entry.scope) }
    }

    static func remembering(_ scope: BaseCalendarScope, for key: String, in storedText: String) -> String {
        var kept = entries(in: storedText).filter { entry in entry.key != key }
        kept.append(StoredEntry(key: key, scope: scope.rawValue))
        let bounded = Array(kept.suffix(maximumRememberedViews))
        guard let data = try? JSONEncoder().encode(bounded) else { return storedText } // Strings always encode.
        return String(decoding: data, as: UTF8.self)
    }

    private struct StoredEntry: Codable {
        let key: String
        let scope: String
    }

    private static func entries(in storedText: String) -> [StoredEntry] {
        (try? JSONDecoder().decode([StoredEntry].self, from: Data(storedText.utf8))) ?? [] // Empty or unreadable: nothing remembered.
    }
}

/// What an entry does wherever it is drawn: a tap opens its note, a drag carries it to another day, a hold offers Open
/// and the moves by a day or a week, and VoiceOver reads its title and dates with the same actions.
struct BaseCalendarEntryInteraction: ViewModifier {
    let entry: BaseCalendarEntry
    /// The day of the entry this part of it stands for.
    let day: CalendarDay
    let context: BaseCalendarContext
    /// False for the parts of a bar after its first in a week, so VoiceOver reads the bar once.
    var isAccessibilityElement = true

    func body(content: Content) -> some View {
        let isMovable = context.moves.canMove(entry.path)
        let title = context.title(of: entry)
        content
            .contentShape(Rectangle())
            .onTapGesture { context.actions.openPath(entry.path) }
            .modifier(BaseCalendarDraggable(payload: BaseCalendarDragPayload.text(path: entry.path, grabbedDay: day), title: title, isDraggable: isMovable))
            .contextMenu {
                Button("Open", systemImage: "arrow.up.forward.square") { context.actions.openPath(entry.path) }
                if isMovable {
                    Section {
                        ForEach(Self.moveChoices, id: \.title) { choice in
                            Button(choice.title, systemImage: choice.systemImage) { context.moves.move(entry.path, choice.dayOffset) }
                        }
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityHidden(!isAccessibilityElement)
            .accessibilityLabel("\(title), \(context.dateText(of: entry))")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { context.actions.openPath(entry.path) }
            .accessibilityActions {
                if isMovable {
                    ForEach(Self.moveChoices, id: \.title) { choice in
                        Button(choice.title) { context.moves.move(entry.path, choice.dayOffset) }
                    }
                }
            }
    }

    static let moveChoices: [(title: String, systemImage: String, dayOffset: Int)] = [
        ("Move to Previous Day", "chevron.left", -1), ("Move to Next Day", "chevron.right", 1),
        ("Move to Previous Week", "chevron.left.2", -7), ("Move to Next Week", "chevron.right.2", 7),
    ]
}

/// Lets an entry be dragged when it can move.
private struct BaseCalendarDraggable: ViewModifier {
    let payload: String
    let title: String
    let isDraggable: Bool

    func body(content: Content) -> some View {
        if isDraggable {
            content.draggable(payload) {
                Label(title, systemImage: "calendar")
                    .padding(8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        } else {
            content
        }
    }
}

/// A day that takes dropped entries, and shows that it will while one is over it. A bar drawn over the day takes
/// them for the day too, without an outline of its own: the day's outline shows.
struct BaseCalendarDropTarget: ViewModifier {
    let day: CalendarDay
    let context: BaseCalendarContext
    var drawsOutline = true

    func body(content: Content) -> some View {
        content
            .overlay {
                if drawsOutline, context.targetedDay == day { RoundedRectangle(cornerRadius: 6).strokeBorder(.tint, lineWidth: 2) }
            }
            .dropDestination(for: String.self) { payloads, _ in
                context.drop(payloads, day)
            } isTargeted: { isTargeted in
                if isTargeted { context.setTargetedDay(day) } else if context.targetedDay == day { context.setTargetedDay(nil) }
            }
    }
}
