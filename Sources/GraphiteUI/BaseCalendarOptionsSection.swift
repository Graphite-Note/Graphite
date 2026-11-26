/**
 * File: BaseCalendarOptionsSection.swift
 * --------------------------------------
 * Layer: UI
 * Description: The Calendar section of Edit View, with the options Calendar Bases offers (Start Date, End Date, Week
 *              Starts On), and how the draft writes them back under the plugin's keys.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import SwiftUI
import GraphiteCore

/// The calendar view's options, as Calendar Bases' view menu offers them.
struct BaseCalendarOptionsSection: View {
    @Binding var draft: BaseViewDraft
    /// Every property the view can read: the note's, the formulas and the file's (its created and modified times).
    let choices: [BasePropertyIdentifier]
    let displayName: (BasePropertyIdentifier) -> String

    var body: some View {
        Section {
            Picker("Start Date", selection: $draft.calendarStartDateProperty) {
                Text("None").tag(BasePropertyIdentifier?.none)
                ForEach(choices, id: \.self) { property in Text(displayName(property)).tag(BasePropertyIdentifier?.some(property)) }
            }
            Picker("End Date", selection: $draft.calendarEndDateProperty) {
                Text("None").tag(BasePropertyIdentifier?.none)
                ForEach(choices, id: \.self) { property in Text(displayName(property)).tag(BasePropertyIdentifier?.some(property)) }
            }
            Picker("Week Starts On", selection: $draft.calendarWeekStartDay) {
                ForEach(BaseCalendarWeekday.allCases, id: \.self) { weekday in Text(weekday.title).tag(weekday) }
            }
        } header: {
            Text("Calendar")
        } footer: {
            Text("Each note is placed on the day of its start date, and over the days to its end date when it has one. "
                 + "Dragging a note to another day changes both dates, when they are the note's own properties.")
        }
    }
}

extension BaseViewDraft {
    /// Writes the calendar options that changed, under the keys Calendar Bases reads.
    func applyCalendarOptions(to editor: inout BaseDefinitionEditor, original: BaseViewDraft, viewPosition: Int) throws {
        if calendarStartDateProperty != original.calendarStartDateProperty {
            try editor.setOption(BaseCalendarOptions.startDateKey, text: calendarStartDateProperty?.rawValue, forViewAt: viewPosition)
        }
        if calendarEndDateProperty != original.calendarEndDateProperty {
            try editor.setOption(BaseCalendarOptions.endDateKey, text: calendarEndDateProperty?.rawValue, forViewAt: viewPosition)
        }
        if calendarWeekStartDay != original.calendarWeekStartDay {
            try editor.setOption(BaseCalendarOptions.weekStartDayKey, text: calendarWeekStartDay.rawValue, forViewAt: viewPosition)
        }
    }
}
