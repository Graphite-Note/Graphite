/**
 * File: BaseCalendarOptions.swift
 * -------------------------------
 * Layer: Core
 * Description: The options of a base's calendar view, read with the keys of the Calendar Bases plugin
 *              (`startDate`, `endDate`, `weekStartDay`).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import Foundation
import Yams

/// The day a calendar's weeks start on, as Calendar Bases writes it (`weekStartDay: monday`).
public enum BaseCalendarWeekday: String, CaseIterable, Hashable, Sendable {
    case sunday, monday, tuesday, wednesday, thursday, friday, saturday

    /// Foundation's number for the day (`Calendar.firstWeekday`): 1 for Sunday.
    public var calendarWeekday: Int {
        (Self.allCases.firstIndex(of: self) ?? 0) + 1
    }

    /// The day's name in English, as the plugin's menu shows it.
    public var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

/// Options of a calendar view, with the keys Calendar Bases (`calendar-bases` 0.2.8) reads, so a `.base` file draws
/// the same calendar in Obsidian with that plugin. Obsidian 1.15 has no calendar view of its own.
public struct BaseCalendarOptions: Hashable, Sendable {
    /// The plugin's week starts on Monday when the file names no day.
    public static let defaultWeekStartDay = BaseCalendarWeekday.monday
    /// The keys the view editor writes, as the plugin names them.
    public static let startDateKey = "startDate"
    public static let endDateKey = "endDate"
    public static let weekStartDayKey = "weekStartDay"

    /// `startDate`: the property that places a note on its first day; no note is placed without it.
    public var startDateProperty: BasePropertyIdentifier?
    /// `endDate`: the property holding a note's last day, for notes that span several days.
    public var endDateProperty: BasePropertyIdentifier?
    /// `weekStartDay`. A day the plugin does not know reads as Monday, as the plugin reads it.
    public var weekStartDay = defaultWeekStartDay

    public init(startDateProperty: BasePropertyIdentifier? = nil, endDateProperty: BasePropertyIdentifier? = nil,
                weekStartDay: BaseCalendarWeekday = defaultWeekStartDay) {
        self.startDateProperty = startDateProperty
        self.endDateProperty = endDateProperty
        self.weekStartDay = weekStartDay
    }

    /// Reads the options from a view's mapping, merge keys and null values already resolved.
    init(viewMapping mapping: Node.Mapping) {
        func property(_ key: String) -> BasePropertyIdentifier? {
            guard let text = mapping[key]?.scalar?.string.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
            return BasePropertyIdentifier(text)
        }
        startDateProperty = property(Self.startDateKey)
        endDateProperty = property(Self.endDateKey)
        let writtenWeekday = mapping[Self.weekStartDayKey]?.scalar?.string.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        weekStartDay = BaseCalendarWeekday(rawValue: writtenWeekday) ?? Self.defaultWeekStartDay
    }

    /// Whether moving a note to another day can write its dates: both properties are the note's own, as the plugin
    /// requires. A date from a formula or a file property (`file.ctime`) cannot be written.
    public var writesNoteProperties: Bool {
        guard case .note? = startDateProperty else { return false }
        guard let endDateProperty else { return true }
        if case .note = endDateProperty { return true }
        return false
    }
}
