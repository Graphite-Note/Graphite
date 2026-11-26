/**
 * File: WorkspaceCalendarCopy.swift
 * ---------------------------------
 * Layer: UI
 * Description: The Calendar Copy core plugin for the open vault: when copies of a base's calendar view into Apple
 *              Calendar run, what each one did, and removing the copied events.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import Foundation
import Observation
import GraphiteCore
import GraphiteApple
import GraphiteIndex

/// What a copy of the open vault reads.
struct CalendarCopySource {
    let vaultName: String
    let store: VaultStore
    let index: VaultIndex
    let settings: CalendarCopySettings
}

/// The Calendar Copy core plugin for the open vault. A copy runs a few seconds after the index takes in changes, one
/// at a time, and compares the chosen view's notes with Graphite's events of that vault in the "Graphite" calendar:
/// the calendar is derived data, rebuilt from the vault by every copy, and never read back into a note.
@MainActor @Observable
final class CalendarCopyController {
    enum Status: Equatable {
        case idle
        case copying
        case copied(CalendarCopyReport, finishedAt: Date)
        case removed(CalendarCopyReport, calendarRemoved: Bool, finishedAt: Date)
        case failed(String, finishedAt: Date)
    }

    /// How long a copy waits after the index changes, so a run of saves makes one copy.
    static let settleDelay: Duration = .seconds(5)
    /// The device's "Graphite" calendar, by EventKit's identifier, which differs from device to device.
    static let calendarIdentifierKey = "GraphiteCalendarCopyCalendar"

    private(set) var status: Status = .idle
    private let clock: any ApplicationClock
    private let store: any CalendarCopyStore
    private let defaults: UserDefaults
    /// The moment the copied window is counted from; tests give a fixed one.
    @ObservationIgnored var currentDate: () -> Date = { .now }
    @ObservationIgnored private var scheduledCopy: Task<Void, Never>?
    @ObservationIgnored private var runningWork: Task<Void, Never>?

    init(clock: any ApplicationClock, store: any CalendarCopyStore, defaults: UserDefaults) {
        self.clock = clock
        self.store = store
        self.defaults = defaults
    }

    var isCopyScheduled: Bool { scheduledCopy != nil }
    var isWorking: Bool { runningWork != nil }

    /// Copies after `settleDelay`, replacing a copy scheduled earlier. An automatic copy never asks for access.
    func schedule(_ source: CalendarCopySource) {
        scheduledCopy?.cancel()
        scheduledCopy = Task { [clock] in
            do { try await clock.sleep(for: Self.settleDelay) } catch { return } // Replaced by a later change, or stopped.
            scheduledCopy = nil
            start { await self.copy(source, asksForAccess: false) }
        }
    }

    /// Copies now, asking for calendar access when the person never answered: Copy Now, choosing a base, turning on.
    func copyNow(_ source: CalendarCopySource) {
        scheduledCopy?.cancel()
        scheduledCopy = nil
        start { await self.copy(source, asksForAccess: true) }
    }

    /// Removes every event Graphite copied from this vault, in any year, then the calendar once nothing is left in it.
    func removeCopiedEvents(vaultName: String) {
        scheduledCopy?.cancel()
        scheduledCopy = nil
        start { await self.remove(vaultName: vaultName) }
    }

    /// Stops copying: the vault closed or the plugin was turned off. Work already sent to EventKit finishes there.
    func stop() {
        scheduledCopy?.cancel()
        scheduledCopy = nil
        runningWork?.cancel()
        runningWork = nil
        if status == .copying { status = .idle }
    }

    /// Runs `work` after the work already running, so two copies never write the calendar at once.
    private func start(_ work: @escaping @MainActor () async -> Void) {
        let previousWork = runningWork
        let task = Task {
            await previousWork?.value
            guard !Task.isCancelled else { return }
            await work()
        }
        runningWork = task
        Task {
            await task.value
            if runningWork == task { runningWork = nil }
        }
    }

    // MARK: Copying

    private func copy(_ source: CalendarCopySource, asksForAccess: Bool) async {
        status = .copying
        do {
            let report = try await copyingReport(source, asksForAccess: asksForAccess)
            guard !Task.isCancelled else { return }
            status = .copied(report, finishedAt: .now)
        } catch is CancellationError {
            if status == .copying { status = .idle }
        } catch {
            status = .failed(Self.message(for: error), finishedAt: .now)
        }
    }

    private func copyingReport(_ source: CalendarCopySource, asksForAccess: Bool) async throws -> CalendarCopyReport {
        guard let basePath = source.settings.basePath, source.settings.isChosen else { throw CalendarCopyFailure.nothingChosen }
        try await ensureAccess(asking: asksForAccess)
        let (entries, titles) = try await chosenEntries(basePath: basePath, viewName: source.settings.viewName, source: source)
        try Task.checkCancellation()
        let dayCalendar = BaseDateFormatting.displayCalendar
        let window = CalendarCopyEvents.window(around: currentDate(), calendar: dayCalendar)
        let events = CalendarCopyEvents.events(of: entries, titles: titles, vaultName: source.vaultName, window: window, calendar: dayCalendar)
        let calendarIdentifier = try await store.calendar(knownIdentifier: defaults.string(forKey: Self.calendarIdentifierKey),
                                                          title: CalendarCopyEvents.calendarTitle)
        defaults.set(calendarIdentifier, forKey: Self.calendarIdentifierKey)
        let existing = try await store.events(inCalendar: calendarIdentifier, during: window)
        try Task.checkCancellation()
        let plan = CalendarCopyPlan.plan(copying: events, over: existing, ownedLinkPrefix: CalendarCopyEvents.ownedLinkPrefix(vaultName: source.vaultName))
        guard !plan.isEmpty else { return CalendarCopyReport() }
        return try await store.apply(plan, inCalendar: calendarIdentifier)
    }

    /// The entries of the chosen view, run as the base runs it on screen, and their titles.
    private func chosenEntries(basePath: VaultPath, viewName: String, source: CalendarCopySource) async throws -> ([BaseCalendarEntry], [VaultPath: String]) {
        let model = BaseDocumentModel(source: .file(basePath), contextPath: basePath, store: source.store, index: source.index, preferredViewName: viewName)
        model.releaseLoadedRecords()
        await model.reload()
        if let loadErrorMessage = model.loadErrorMessage { throw CalendarCopyFailure.baseUnreadable(basePath, loadErrorMessage) }
        guard model.viewSelectionErrorMessage == nil, let result = model.result, result.view.name == viewName else {
            throw CalendarCopyFailure.viewMissing(basePath, viewName)
        }
        guard result.view.type == .calendar, result.view.calendar.startDateProperty != nil else { throw CalendarCopyFailure.notACalendar(viewName) }
        if let actionErrorMessage = model.actionErrorMessage { throw CalendarCopyFailure.baseUnreadable(basePath, actionErrorMessage) }
        let calendar = BaseCalendarLayout.calendar(weekStartDay: result.view.calendar.weekStartDay)
        let titles = Dictionary(result.rows.map { row in (row.path, BaseCalendarEntry.title(of: row, columns: result.columns)) },
                                uniquingKeysWith: { first, _ in first })
        return (BaseCalendarEntry.entries(of: result, calendar: calendar), titles)
    }

    private func ensureAccess(asking: Bool) async throws {
        var access = await store.access()
        if access == .notAsked, asking { access = await store.requestAccess() }
        guard access.canRead else { throw access == .notAsked ? CalendarCopyFailure.accessNotAsked : CalendarCopyStoreError.accessRefused }
    }

    // MARK: Removing

    private func remove(vaultName: String) async {
        status = .copying
        do {
            try await ensureAccess(asking: true)
            guard let calendarIdentifier = defaults.string(forKey: Self.calendarIdentifierKey) else {
                status = .removed(CalendarCopyReport(), calendarRemoved: false, finishedAt: .now)
                return
            }
            var report = CalendarCopyReport()
            let ownedLinkPrefix = CalendarCopyEvents.ownedLinkPrefix(vaultName: vaultName)
            for window in CalendarCopyEvents.searchWindows(calendar: BaseDateFormatting.displayCalendar) {
                try Task.checkCancellation()
                let existing = try await store.events(inCalendar: calendarIdentifier, during: window)
                let plan = CalendarCopyPlan.plan(copying: [], over: existing, ownedLinkPrefix: ownedLinkPrefix)
                guard !plan.isEmpty else { continue }
                report.removedCount += try await store.apply(plan, inCalendar: calendarIdentifier).removedCount
            }
            let calendarRemoved = try await store.removeCalendarIfEmpty(calendarIdentifier)
            if calendarRemoved { defaults.removeObject(forKey: Self.calendarIdentifierKey) }
            status = .removed(report, calendarRemoved: calendarRemoved, finishedAt: .now)
        } catch is CancellationError {
            if status == .copying { status = .idle }
        } catch {
            status = .failed(Self.message(for: error), finishedAt: .now)
        }
    }

    static func message(for error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "The copy to Calendar failed. Try again with Copy Now."
    }
}

/// Why a copy did not run.
enum CalendarCopyFailure: LocalizedError, Equatable {
    case nothingChosen
    case accessNotAsked
    case baseUnreadable(VaultPath, String)
    case viewMissing(VaultPath, String)
    case notACalendar(String)

    var errorDescription: String? {
        switch self {
        case .nothingChosen: "Choose a base and its calendar view to copy."
        case .accessNotAsked: "Graphite needs access to your calendars. Tap Copy Now to allow it."
        case .baseUnreadable(let path, let reason): "“\(path.name)” could not be read. \(reason)"
        case .viewMissing(let path, let viewName): "“\(path.name)” has no view named “\(viewName)”. Choose another view."
        case .notACalendar(let viewName): "“\(viewName)” is not a calendar view with a start date. Choose its Start Date in Edit View, or another view."
        }
    }
}

/// The Calendar Copy core plugin.
extension WorkspaceModel {
    /// What a copy of the open vault reads, or nil when there is nothing to copy: the plugin is off, no vault is open,
    /// or the index has not read the whole vault (a note it does not hold yet would be removed from the calendar).
    func calendarCopySource() async -> CalendarCopySource? {
        guard preferences.isEnabled(.calendarCopy), hasCompletedIndexScan, let index, let store, let currentVaultIdentifier,
              let vault = vaultLibrary.vault(withIdentifier: currentVaultIdentifier) else { return nil }
        let settings = (try? await store.calendarCopySettings()) ?? CalendarCopySettings() // An unreadable file: nothing chosen, and it is left as it is.
        return CalendarCopySource(vaultName: vault.name, store: store, index: index, settings: settings)
    }

    /// After the index takes in changes, and once a scan of the vault ends.
    func scheduleCalendarCopy() {
        guard preferences.isEnabled(.calendarCopy), hasCompletedIndexScan else { return }
        Task {
            guard let source = await calendarCopySource(), source.settings.isChosen else { return }
            calendarCopy.schedule(source)
        }
    }

    /// Copy Now, after a base is chosen, and when the plugin is turned on.
    func copyToCalendarNow() {
        Task {
            guard let source = await calendarCopySource() else { return }
            calendarCopy.copyNow(source)
        }
    }

    func removeCopiedCalendarEvents() {
        guard let currentVaultIdentifier, let vault = vaultLibrary.vault(withIdentifier: currentVaultIdentifier) else { return }
        calendarCopy.removeCopiedEvents(vaultName: vault.name)
    }
}
