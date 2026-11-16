/**
 * File: WorkspaceCalendar.swift
 * -----------------------------
 * Layer: UI
 * Description: The Calendar core plugin's events in the open vault: the days that have a daily note, a day's events
 *              as a Markdown list at the cursor or in a template's `{{events}}`, and the note made from an event.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

import Foundation
import GraphiteCore
import GraphiteApple

/// The Calendar core plugin's events in the open vault. Calendar access is asked only by what needs events, at its
/// first use: showing a day's events, inserting them, filling `{{events}}`, or making a note of the current event.
extension WorkspaceModel {
    /// The person's own calendar: their time zone, region and first weekday.
    var personalCalendar: Calendar { .autoupdatingCurrent }

    /// Whether Graphite may read the person's calendars or reminders, asking when they never answered and `asking` is true.
    func calendarAccess(to entity: CalendarStoreEntity, asking: Bool) async -> CalendarAccess {
        let store = processServices.calendar.store
        var access = store.access(to: entity)
        if asking, access == .notAsked { access = await store.requestAccess(to: entity) }
        // Linked tasks are kept ticked alike only on a device where the person used Reminders through Graphite.
        if entity == .reminders, asking, access.canRead { deviceDefaults.set(true, forKey: Self.usesRemindersKey) }
        return access
    }

    /// Set once the person used a Reminders feature of Graphite on this device; until then, coming to the front reads
    /// nothing of Reminders.
    static let usesRemindersKey = "GraphiteUsesReminders"

    /// The days that have a daily note in the daily notes folder, read from the index's paths against the format.
    func dailyNoteDays() async -> Set<CalendarDay> {
        guard let index, let settings = dailyNoteSettingsReading.settings,
              let reader = MomentDateReader(format: settings.format, languages: preferences.dateNames.readingLanguages),
              let candidates = try? await index.paths(inside: dailyNotesFolder(of: settings)) else { return [] } // No index yet: no marks.
        let calendar = personalCalendar
        // Every path of the folder is read against the format: off the main actor, with the format prepared once.
        return await Task.detached(priority: .userInitiated) {
            Set(candidates.compactMap { path in settings.date(ofNoteAt: path, using: reader).map { date in CalendarDay(date, in: calendar) } })
        }.value
    }

    /// The day the daily note at `path` is for; nil when it is not a daily note.
    func dailyNoteDay(of path: VaultPath) -> CalendarDay? {
        guard preferences.isEnabled(.dailyNotes), let settings = dailyNoteSettingsReading.settings else { return nil }
        return settings.date(ofNoteAt: path, languages: preferences.dateNames.readingLanguages).map { date in CalendarDay(date, in: personalCalendar) }
    }

    /// Opens the daily note of `day`, made from the daily note template when it does not exist yet.
    func openDailyNote(on day: CalendarDay) async {
        guard let date = day.startDate(in: personalCalendar) else { return }
        await openDailyNote(for: date)
    }

    /// The events of `day`, in the order the list writes them. Throws without calendar access.
    func calendarEvents(on day: CalendarDay) async throws -> [CalendarEvent] {
        let calendar = personalCalendar
        guard let start = day.startDate(in: calendar), let end = day.adding(days: 1, in: calendar).startDate(in: calendar) else { return [] }
        return CalendarEventList.events(try await processServices.calendar.store.events(from: start, to: end), on: day, calendar: calendar)
    }

    /// `day`'s events as a Markdown list, each event that has a note linking to it from `note`. Throws without access.
    func calendarEventList(on day: CalendarDay, linkingFrom note: VaultPath?) async throws -> String {
        let events = try await calendarEvents(on: day)
        guard !events.isEmpty else { return "" }
        var links: [String: String] = [:]
        if let vaultStore = store, let note {
            for event in events {
                let path = try await eventNotePath(for: event, store: vaultStore)
                if try await vaultStore.fileExists(path) { links[event.id] = await linkText(for: path, in: note) }
            }
        }
        return CalendarEventList.markdown(for: events, on: day, calendar: personalCalendar, timeFormat: templateSettings.timeFormat,
                                          language: preferences.dateNames.language) { event in links[event.id] }
    }

    /// Inserts the day's events at the cursor of `session`'s note: the daily note's own day, or today in another note.
    func insertCalendarEvents(into session: MarkdownSession) async {
        let day = dailyNoteDay(of: session.path) ?? CalendarDay(.now, in: personalCalendar)
        guard await calendarAccess(to: .events, asking: true).canRead else {
            errorMessage = CalendarStoreError.accessRefused(.events).errorDescription
            return
        }
        do {
            let list = try await calendarEventList(on: day, linkingFrom: session.path)
            guard !list.isEmpty else {
                notice = "There are no events on \(day.isoText) in your calendars."
                return
            }
            session.apply(BlockInsertion.edit(inserting: list, into: session.text, at: session.selection))
        } catch { errorMessage = CalendarFailureWording.words(for: error, doing: .readingEvents) }
    }

    /// `rendered` with `{{events}}` filled in with `day`'s events, when the Calendar core plugin is on; with it off, the
    /// variable stays as written, as Obsidian leaves it. Without calendar access the list is empty and the person is told.
    func fillingCalendarEvents(in rendered: String, on day: CalendarDay, note: VaultPath) async -> String {
        guard preferences.isEnabled(.calendar), CalendarTemplateVariable.appears(in: rendered) else { return rendered }
        guard await calendarAccess(to: .events, asking: true).canRead else {
            notice = "{{events}} was left empty: Graphite cannot read your calendars. Allow it in Settings › Privacy & Security › Calendars."
            return CalendarTemplateVariable.filled(rendered, eventList: "")
        }
        do {
            return CalendarTemplateVariable.filled(rendered, eventList: try await calendarEventList(on: day, linkingFrom: note))
        } catch {
            notice = "{{events}} was left empty. " + CalendarFailureWording.words(for: error, doing: .readingEvents)
            return CalendarTemplateVariable.filled(rendered, eventList: "")
        }
    }

    // MARK: Event notes

    /// Where the note of `event` is: its calendar's folder, else the plugin's default folder, else the vault's location
    /// for new notes; named by day and title.
    func eventNotePath(for event: CalendarEvent, store vaultStore: VaultStore) async throws -> VaultPath {
        let settings = (try? await vaultStore.calendarSettings()) ?? CalendarSettings() // An unreadable file: the defaults.
        let folder = settings.eventNoteFolder(forCalendarTitled: event.calendarTitle) ?? newFileDirectory(nil)
        return try folder.appending(EventNote.fileStem(for: event, calendar: personalCalendar) + ".md")
    }

    /// Opens the note of `event`, making it first, with the event's properties, when it does not exist yet.
    func openNote(for event: CalendarEvent) async {
        guard let vaultStore = store else { return }
        do {
            let path = try await eventNotePath(for: event, store: vaultStore)
            if try await !vaultStore.fileExists(path) {
                try await vaultStore.createDirectory(path.parent)
                _ = try await vaultStore.save(Data(EventNote.text(for: event, calendar: personalCalendar).utf8), at: path, expecting: .absent)
                refreshIndex(for: [path])
                await open(path)
                await showInListings(path)
                return
            }
            await open(path)
        } catch { errorMessage = CalendarFailureWording.words(for: error, doing: .makingEventNote) }
    }

    /// Opens the note of the event under way, or else of today's next one.
    func openNoteForCurrentEvent(at moment: Date) async {
        guard await calendarAccess(to: .events, asking: true).canRead else {
            errorMessage = CalendarStoreError.accessRefused(.events).errorDescription
            return
        }
        do {
            let events = try await calendarEvents(on: CalendarDay(moment, in: personalCalendar)).filter { event in !event.isAllDay }
            let underWay = events.first { event in event.isUnderWay(at: moment) }
            guard let event = underWay ?? events.first(where: { event in event.startDate > moment }) else {
                notice = "No event is under way or still to come today."
                return
            }
            await openNote(for: event)
        } catch { errorMessage = CalendarFailureWording.words(for: error, doing: .readingEvents) }
    }

    // MARK: Settings

    /// The vault's Calendar settings; the defaults when no vault is open or the file cannot be read.
    func calendarSettings() async -> CalendarSettings {
        (try? await store?.calendarSettings()) ?? CalendarSettings() // An unreadable file: the defaults, and it is left as it is.
    }

    func updateCalendarSettings(_ settings: CalendarSettings) async {
        guard let store else { return }
        do { try await store.saveCalendarSettings(settings) } catch { errorMessage = CalendarFailureWording.words(for: error, doing: .savingSettings) }
    }

    /// What Settings › Calendar reads and changes.
    func calendarSettingsActions() -> CalendarSettingsActions {
        CalendarSettingsActions(
            hasVault: store != nil,
            settings: { [weak self] in await self?.calendarSettings() ?? CalendarSettings() },
            saveSettings: { [weak self] settings in await self?.updateCalendarSettings(settings) },
            access: { [weak self] entity, asking in await self?.calendarAccess(to: entity, asking: asking) ?? .refused },
            lists: { [weak self] entity in self?.calendarLists(of: entity) ?? [] })
    }

    /// The person's calendars or Reminders lists, by title; none without access.
    func calendarLists(of entity: CalendarStoreEntity) -> [CalendarList] {
        guard processServices.calendar.store.access(to: entity).canRead else { return [] }
        return (try? processServices.calendar.store.lists(of: entity)) ?? [] // Refused meanwhile: none.
    }

    // MARK: The panel

    /// What the calendar panel asks of the workspace.
    func calendarPanelActions() -> CalendarPanelActions {
        CalendarPanelActions(
            dailyNoteDays: { [weak self] in await self?.dailyNoteDays() ?? [] },
            eventAccess: { [weak self] asking in await self?.calendarAccess(to: .events, asking: asking) ?? .refused },
            events: { [weak self] day in try await self?.calendarEvents(on: day) ?? [] },
            openDailyNote: { [weak self] day in await self?.openDailyNote(on: day) },
            openEventNote: { [weak self] event in await self?.openNote(for: event) },
            opensDailyNotes: preferences.isEnabled(.dailyNotes))
    }

    // MARK: Commands

    /// The Calendar core plugin's commands of a note being edited: its events, and its tasks and reminders.
    func calendarNoteCommands(session: MarkdownSession) -> [PaletteCommand] {
        guard preferences.isEnabled(.calendar), session.viewMode != .reading else { return [] }
        return [
            PaletteCommand(id: "calendar-insert-events", command: .insertCalendarEvents, systemImage: "calendar.day.timeline.left") { [weak self] in
                Task { await self?.insertCalendarEvents(into: session) }
            },
            PaletteCommand(id: "reminders-send-task", command: .sendTaskToReminders, systemImage: "checklist.checked") { [weak self] in
                Task { await self?.sendTaskToReminders(from: session) }
            },
            PaletteCommand(id: "reminders-insert", command: .insertReminders, systemImage: "list.bullet.rectangle") { [weak self] in
                Task { await self?.insertReminders(into: session) }
            },
        ]
    }
}
