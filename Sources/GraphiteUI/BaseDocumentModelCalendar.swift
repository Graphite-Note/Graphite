/**
 * File: BaseDocumentModelCalendar.swift
 * -------------------------------------
 * Layer: UI
 * Description: Moving a note to another day of a base's calendar view: which notes can move, and the one checked
 *              save that shifts their start and end dates.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import Foundation
import GraphiteCore

extension BaseDocumentModel {
    /// The calendar view of `result`, moving its entries through this model, offering `editView` only when `canEditView`.
    func calendarView(of result: BaseQueryResult, actions: BaseViewActions, canEditView: Bool, editView: @escaping () -> Void) -> BaseCalendarView {
        let moves = BaseCalendarMoves(canMove: { [weak self] path in self?.canReschedule(path) ?? false },
                                      move: { [weak self] path, dayOffset in Task { await self?.reschedule(path, byDays: dayOffset) } })
        return BaseCalendarView(result: result, actions: actions, layoutMemoryKey: calendarLayoutMemoryKey(viewName: result.view.name), moves: moves,
                                editView: canEditView ? editView : nil)
    }

    /// Where a calendar view's Month or Week choice is remembered in the window: the base file and the view's name, or
    /// the note holding a base code block.
    func calendarLayoutMemoryKey(viewName: String) -> String {
        switch source {
        case .file(let path): path.rawValue + "#" + viewName
        case .inline: contextPath.rawValue + "#" + viewName
        }
    }

    /// Whether a calendar entry can be moved to another day: the view's dates are note properties the base may write,
    /// as Calendar Bases requires, and the entry's row is a note other than the one embedding the base.
    func canReschedule(_ path: VaultPath) -> Bool {
        guard let view = selectedView, view.type == .calendar, view.calendar.writesNoteProperties,
              let startProperty = view.calendar.startDateProperty, canEdit(startProperty, of: path) else { return false }
        return view.calendar.endDateProperty.map { endProperty in canEdit(endProperty, of: path) } ?? true
    }

    /// Moves a calendar entry by `dayOffset` days: its start, and its end when it has one, shift together in one
    /// revision-checked save, each keeping the form the note wrote (`BaseCalendarRescheduling`). The moved dates are
    /// counted from those the view shows, which the base reads again after every change of the vault, as the board's
    /// moves write the column the person sees.
    /// - Returns: Whether the note was saved (or the offset was zero).
    @discardableResult
    func reschedule(_ path: VaultPath, byDays dayOffset: Int) async -> Bool {
        guard dayOffset != 0 else { return true }
        guard canReschedule(path), let view = selectedView, let startProperty = view.calendar.startDateProperty,
              let row = result?.rows.first(where: { row in row.path == path }), let start = row.presentation.calendarStart else { return false }
        let calendar = BaseCalendarLayout.calendar(weekStartDay: view.calendar.weekStartDay)
        var writes = [BasePropertyWrite(property: startProperty, value: BaseCalendarRescheduling.writtenValue(
            BaseCalendarRescheduling.moved(start, byDays: dayOffset, calendar: calendar), calendar: calendar))]
        if let endProperty = view.calendar.endDateProperty, let end = row.presentation.calendarEnd {
            writes.append(BasePropertyWrite(property: endProperty, value: BaseCalendarRescheduling.writtenValue(
                BaseCalendarRescheduling.moved(end, byDays: dayOffset, calendar: calendar), calendar: calendar)))
        }
        return await setProperties(writes, of: path)
    }
}
