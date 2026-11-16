/**
 * File: CalendarSettingsPage.swift
 * --------------------------------
 * Layer: UI
 * Description: Settings › Calendar: whether Graphite may read Calendar and Reminders, the folder of each calendar's
 *              event notes, and the Reminders lists tasks are sent to and brought in from.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

import SwiftUI
import GraphiteCore
import GraphiteApple

/// What Settings › Calendar reads and changes.
struct CalendarSettingsActions {
    /// Whether a vault is open, whose settings the page shows.
    let hasVault: Bool
    let settings: @MainActor () async -> CalendarSettings
    let saveSettings: @MainActor (CalendarSettings) async -> Void
    /// Calendar or Reminders access, asking the person when they never answered and the argument is true.
    let access: @MainActor (CalendarStoreEntity, _ asking: Bool) async -> CalendarAccess
    let lists: @MainActor (CalendarStoreEntity) -> [CalendarList]
}

/// Settings › Calendar. The settings are the vault's (`.obsidian/graphite-calendar.json`); access is the device's, and
/// is asked here only when the person taps Allow.
struct CalendarSettingsPage: View {
    let actions: CalendarSettingsActions
    @State private var draft = CalendarSettings()
    @State private var savedSettings = CalendarSettings()
    @State private var eventAccess = CalendarAccess.notAsked
    @State private var reminderAccess = CalendarAccess.notAsked
    @State private var calendars: [CalendarList] = []
    @State private var reminderLists: [CalendarList] = []

    var body: some View {
        Form {
            if !actions.hasVault { SettingsNeedAVault(what: "calendar settings") }
            Section {
                accessRow("Calendars", access: eventAccess, entity: .events)
                accessRow("Reminders", access: reminderAccess, entity: .reminders)
            } header: {
                Text("Access")
            } footer: {
                Text("Graphite asks once, when you first use a feature. What it reads stays on this device, and goes into a note only "
                     + "when you ask.")
                    .formFooterAlignment()
            }
            Section {
                SettingsTextField(title: "Default Folder", prompt: "Location for new notes", text: $draft.defaultEventNoteFolder, submit: save)
                ForEach(calendars) { calendar in
                    SettingsTextField(title: calendar.title, prompt: "Default folder", text: folderBinding(forCalendarTitled: calendar.title), submit: save)
                }
            } header: {
                Text("Event Notes")
            } footer: {
                Text("Choosing an event in the calendar panel opens its note, made the first time with the event's date, times, place "
                     + "and attendees as properties, and named by its day and title, as “2026-11-12 Lecture”.")
                    .formFooterAlignment()
            }
            Section {
                Picker("Send Tasks To", selection: $draft.taskListTitle) {
                    Text("Default List").tag("")
                    ForEach(listTitles(including: draft.taskListTitle), id: \.self) { title in Text(title).tag(title) }
                }
                Picker("Insert Reminders From", selection: $draft.importedListTitle) {
                    Text("All Lists").tag("")
                    ForEach(listTitles(including: draft.importedListTitle), id: \.self) { title in Text(title).tag(title) }
                }
            } header: {
                Text("Reminders")
            } footer: {
                Text("“Reminders: Send task to Reminders” sends the task at the cursor with its 📅 due date, and links the two with a "
                     + "block ID such as ^reminder-k3j9x2ab at the end of the task's line. Ticking either one ticks the other when Graphite "
                     + "comes to the front or leaves it. Graphite never deletes a reminder.")
                    .formFooterAlignment()
            }
        }
        .disabled(!actions.hasVault)
        .navigationTitle("Calendar")
        .task { await load() }
        .onChange(of: draft.taskListTitle) { save() }
        .onChange(of: draft.importedListTitle) { save() }
        .onDisappear(perform: save)
    }

    private func accessRow(_ title: String, access: CalendarAccess, entity: CalendarStoreEntity) -> some View {
        LabeledContent(title) {
            switch access {
            case .notAsked:
                Button("Allow…") { Task { await allow(entity) } }
            case .granted: Text("Allowed")
            case .writeOnly, .refused: Text("Not Allowed")
            case .restricted: Text("Restricted")
            }
        }
    }

    /// The lists offered, with the chosen one kept while it is not among them, as before access is allowed.
    private func listTitles(including chosenTitle: String) -> [String] {
        let titles = reminderLists.map(\.title)
        return chosenTitle.isEmpty || titles.contains(chosenTitle) ? titles : titles + [chosenTitle]
    }

    private func folderBinding(forCalendarTitled calendarTitle: String) -> Binding<String> {
        Binding(get: { draft.eventNoteFolders[calendarTitle] ?? "" }, set: { folder in draft.eventNoteFolders[calendarTitle] = folder })
    }

    private func load() async {
        let loaded = await actions.settings()
        draft = loaded
        savedSettings = loaded
        await readAccess(asking: nil)
    }

    private func allow(_ entity: CalendarStoreEntity) async {
        await readAccess(asking: entity)
    }

    private func readAccess(asking entity: CalendarStoreEntity?) async {
        eventAccess = await actions.access(.events, entity == .events)
        reminderAccess = await actions.access(.reminders, entity == .reminders)
        calendars = actions.lists(.events)
        reminderLists = actions.lists(.reminders)
    }

    private func save() {
        var settings = draft
        settings.defaultEventNoteFolder = settings.defaultEventNoteFolder.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        settings.eventNoteFolders = settings.eventNoteFolders.mapValues { folder in folder.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")) }
            .filter { _, folder in !folder.isEmpty }
        guard settings != savedSettings else { return }
        savedSettings = settings
        Task { await actions.saveSettings(settings) }
    }
}
