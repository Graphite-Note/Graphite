/**
 * File: CalendarCopySettingsPage.swift
 * ------------------------------------
 * Layer: UI
 * Description: Settings › Calendar Copy: the base and calendar view copied into Apple Calendar, Copy Now, what the last
 *              copy did, and removing the copied events.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import SwiftUI
import GraphiteCore
import GraphiteApple

/// What Settings › Calendar Copy reads and changes.
struct CalendarCopySettingsActions {
    let hasVault: Bool
    /// The vault's choice (`copiedBase` in `.obsidian/graphite-calendar.json`).
    let settings: @MainActor () async -> CalendarCopySettings
    let saveSettings: @MainActor (CalendarCopySettings) async -> String?
    /// The vault's `.base` files, at most `CalendarCopySettingsPage.maximumListedBases`.
    let baseFiles: @MainActor () async -> [VaultPath]
    /// The names of a base's calendar views.
    let calendarViewNames: @MainActor (VaultPath) async -> [String]
    let copyNow: @MainActor () -> Void
    let removeCopiedEvents: @MainActor () -> Void
}

/// Settings › Calendar Copy. The choice of base is the vault's; whether this device copies is the plugin's switch.
struct CalendarCopySettingsPage: View {
    static let maximumListedBases = 500

    let controller: CalendarCopyController
    let actions: CalendarCopySettingsActions
    @State private var settings = CalendarCopySettings()
    @State private var baseFiles: [VaultPath] = []
    @State private var viewNames: [String] = []
    @State private var saveError: String?
    @State private var confirmsRemoval = false

    var body: some View {
        Form {
            if !actions.hasVault { SettingsNeedAVault(what: "calendar copy") }
            choiceSection
            copySection
            removalSection
        }
        .formStyle(.grouped)
        .navigationTitle("Calendar Copy")
        .confirmationDialog("Remove the events copied from this vault?", isPresented: $confirmsRemoval, titleVisibility: .visible) {
            Button("Remove Copied Events", role: .destructive) { actions.removeCopiedEvents() }
        } message: {
            Text("The notes stay as they are. Copy Now puts the events back.")
        }
        .task {
            guard actions.hasVault else { return }
            settings = await actions.settings()
            baseFiles = await actions.baseFiles()
            if let basePath = settings.basePath {
                if !baseFiles.contains(basePath) { baseFiles.insert(basePath, at: 0) }
                viewNames = await actions.calendarViewNames(basePath)
            }
        }
    }

    private var choiceSection: some View {
        Section {
            Picker("Base", selection: Binding(get: { settings.basePath }, set: { path in chooseBase(path) })) {
                Text("None").tag(VaultPath?.none)
                ForEach(baseFiles, id: \.self) { path in Text(path.rawValue).tag(VaultPath?.some(path)) }
            }
            Picker("Calendar View", selection: Binding(get: { settings.viewName }, set: { name in chooseView(name) })) {
                if viewNames.isEmpty { Text("None").tag("") }
                ForEach(viewNames, id: \.self) { name in Text(name).tag(name) }
            }
            .disabled(viewNames.isEmpty)
        } header: {
            Text("Copied Notes")
        } footer: {
            Text("Each note of the view becomes an event of a “Graphite” calendar, on the days the view places it, from a year ago to three "
                 + "years ahead. Only bases with a calendar view are copied: add one with New View › Calendar.")
                .formFooterAlignment()
        }
    }

    private var copySection: some View {
        Section {
            Button("Copy Now", systemImage: "arrow.triangle.2.circlepath") { actions.copyNow() }
                .disabled(!settings.isChosen || controller.isWorking)
            statusRow
        } footer: {
            Text("Notes are copied a few seconds after they change and when the vault opens. Graphite changes only the events it copied "
                 + "from this vault, and never changes a note: an event edited in Calendar is put back at the next copy.")
                .formFooterAlignment()
        }
    }

    private var removalSection: some View {
        Section {
            Button("Remove Copied Events…", systemImage: "calendar.badge.minus", role: .destructive) { confirmsRemoval = true }
                .disabled(controller.isWorking)
        } footer: {
            Text("Removes the events copied from this vault, then the “Graphite” calendar once nothing else is in it. Turning Calendar "
                 + "Copy off stops the copies and leaves the calendar as it is.")
                .formFooterAlignment()
        }
    }

    @ViewBuilder private var statusRow: some View {
        switch controller.status {
        case .idle:
            EmptyView()
        case .copying:
            Label("Copying…", systemImage: "hourglass").foregroundStyle(.secondary)
        case .copied(let report, let finishedAt):
            Label(Self.summary(of: report, finishedAt: finishedAt), systemImage: "checkmark.circle").foregroundStyle(.secondary)
        case .removed(let report, let calendarRemoved, let finishedAt):
            let calendarText = calendarRemoved ? " The “Graphite” calendar was removed." : ""
            Label("Removed \(Self.eventCount(report.removedCount)) at \(finishedAt.formatted(date: .omitted, time: .shortened)).\(calendarText)",
                  systemImage: "checkmark.circle")
                .foregroundStyle(.secondary)
        case .failed(let message, _):
            Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
        }
        if let saveError { Label(saveError, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
    }

    static func summary(of report: CalendarCopyReport, finishedAt: Date) -> String {
        let time = finishedAt.formatted(date: .omitted, time: .shortened)
        guard report != CalendarCopyReport() else { return "Calendar matched the notes at \(time)." }
        return "Copied at \(time): \(report.addedCount) added, \(report.changedCount) changed, \(report.removedCount) removed."
    }

    static func eventCount(_ count: Int) -> String { count == 1 ? "1 event" : "\(count) events" }

    private func chooseBase(_ path: VaultPath?) {
        Task {
            if let path { viewNames = await actions.calendarViewNames(path) } else { viewNames = [] }
            await save(CalendarCopySettings(basePath: path, viewName: viewNames.first ?? ""))
        }
    }

    private func chooseView(_ name: String) {
        Task { await save(CalendarCopySettings(basePath: settings.basePath, viewName: name)) }
    }

    private func save(_ newSettings: CalendarCopySettings) async {
        guard newSettings != settings else { return }
        saveError = await actions.saveSettings(newSettings)
        guard saveError == nil else { return }
        settings = newSettings
        if newSettings.isChosen { actions.copyNow() }
    }
}

extension WorkspaceModel {
    func calendarCopySettingsActions() -> CalendarCopySettingsActions {
        CalendarCopySettingsActions(
            hasVault: store != nil,
            settings: { [weak self] in (try? await self?.store?.calendarCopySettings()) ?? CalendarCopySettings() }, // Unreadable: nothing chosen.
            saveSettings: { [weak self] settings in
                guard let store = self?.store else { return "Open a vault first." }
                do {
                    try await store.saveCalendarCopySettings(settings)
                    return nil
                } catch {
                    return "The choice could not be saved. " + CalendarCopyController.message(for: error)
                }
            },
            baseFiles: { [weak self] in
                let limit = CalendarCopySettingsPage.maximumListedBases
                let paths = try? await self?.index?.paths(withFileExtension: "base", limit: limit) // No index yet: none listed.
                return paths ?? []
            },
            calendarViewNames: { [weak self] path in await self?.calendarViewNames(in: path) ?? [] },
            copyNow: { [weak self] in self?.copyToCalendarNow() },
            removeCopiedEvents: { [weak self] in self?.removeCopiedCalendarEvents() })
    }

    /// The names of the calendar views of the base at `path`; none when it cannot be read.
    private func calendarViewNames(in path: VaultPath) async -> [String] {
        let snapshot = try? await store?.read(path, maximumBytes: BaseDefinition.maximumSourceBytes) // Unreadable: no view to offer.
        guard let snapshot, let sourceText = String(data: snapshot.data, encoding: .utf8) else { return [] }
        let definition = await Task.detached(priority: .userInitiated) { try? BaseDefinition.parse(sourceText) }.value // Not a base: no view.
        return (definition?.views ?? []).filter { view in view.type == .calendar }.map(\.name)
    }
}
