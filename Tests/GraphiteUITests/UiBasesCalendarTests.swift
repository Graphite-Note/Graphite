/**
 * File: UiBasesCalendarTests.swift
 * --------------------------------
 * Layer: Tests
 * Description: A base's calendar view over a vault: its entries, moving a note to another day in one checked save,
 *              what a drag carries, the remembered Month or Week choice, and Calendar Copy over a calendar store that
 *              answers for EventKit.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 27/11/2026
 */

import XCTest
import GraphiteCore
import GraphiteApple
import GraphiteIndex
@testable import GraphiteUI
import GraphiteTestSupport

@MainActor
final class UiBasesCalendarTests: XCTestCase {
    private var vault: URL!
    private var index: VaultIndex!
    private var store: VaultStore!

    override func setUp() async throws {
        vault = try TemporaryVault.make(prefix: "UiBasesCalendarVault", for: self).root
        index = try VaultIndex(databaseURL: vault.appendingPathExtension("cache").appendingPathComponent("index.sqlite"))
        store = VaultStore(root: vault)
    }

    private func write(_ text: String, to relativePath: String) throws {
        let location = vault.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: location)
    }

    private func text(at relativePath: String) throws -> String {
        try String(contentsOf: vault.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private let labReport = "---\ncourse: Signals\ndue: 2026-12-01\nuntil: 2026-12-03 # three days\n---\nWrite the report.\n"
    private let exam = "---\ncourse: Signals\ndue: 2026-12-03T09:00\n---\n"
    private let reading = "---\ncourse: History\ndue: 2026-12-02\n---\n"

    /// A base of three dated notes with a calendar view, as Calendar Bases writes it.
    private func calendarModel(startDate: String = "note.due", endDate: String = "note.until", embeddedIn contextPath: String? = nil) async throws -> BaseDocumentModel {
        try write(labReport, to: "Courses/Lab report.md")
        try write(exam, to: "Courses/Signals exam.md")
        try write(reading, to: "Courses/Reading.md")
        try write("filters: file.inFolder(\"Courses\")\nformulas:\n  week_later: due + \"7d\"\nviews:\n  - type: calendar\n    name: Deadlines\n    order: [file.name, course]\n    startDate: \(startDate)\n    endDate: \(endDate)\n    weekStartDay: monday\n", to: "Deadlines.base")
        _ = try await index.reconcile(root: vault)
        let basePath = try VaultPath("Deadlines.base")
        let model = BaseDocumentModel(source: .file(basePath), contextPath: try contextPath.map(VaultPath.init) ?? basePath, store: store, index: index)
        await model.reload()
        XCTAssertNil(model.loadErrorMessage)
        XCTAssertEqual(model.selectedView?.type, .calendar)
        return model
    }

    private func entries(_ model: BaseDocumentModel) throws -> [String: (first: String, last: String)] {
        let result = try XCTUnwrap(model.result)
        let calendar = BaseCalendarLayout.calendar(weekStartDay: result.view.calendar.weekStartDay)
        var entries: [String: (first: String, last: String)] = [:]
        for entry in BaseCalendarEntry.entries(of: result, calendar: calendar) { entries[entry.path.stem] = (entry.firstDay.isoText, entry.lastDay.isoText) }
        return entries
    }

    // MARK: The view's entries

    func testEachNoteIsPlacedFromItsStartToItsEnd() async throws {
        let model = try await calendarModel()
        let placed = try entries(model)
        XCTAssertEqual(placed.count, 3)
        XCTAssertEqual(placed["Lab report"]?.first, "2026-12-01")
        XCTAssertEqual(placed["Lab report"]?.last, "2026-12-03")
        XCTAssertEqual(placed["Signals exam"]?.first, "2026-12-03")
        XCTAssertEqual(BaseCalendarView.titles(of: try XCTUnwrap(model.result))[try VaultPath("Courses/Reading.md")], "Reading",
                       "The first property, the file's name, titles the entry.")
    }

    // MARK: Moving

    func testMovingANoteShiftsItsStartAndEndInOneSaveKeepingEverythingElse() async throws {
        let model = try await calendarModel()
        let path = try VaultPath("Courses/Lab report.md")
        XCTAssertTrue(model.canReschedule(path))
        let isMoved = await model.reschedule(path, byDays: 2)
        XCTAssertTrue(isMoved)
        XCTAssertNil(model.actionErrorMessage)
        XCTAssertEqual(try text(at: "Courses/Lab report.md"), "---\ncourse: Signals\ndue: 2026-12-03\nuntil: 2026-12-05 # three days\n---\nWrite the report.\n",
                       "Both dates move together, as dates, and the comment and body stay.")
        XCTAssertEqual(try entries(model)["Lab report"]?.first, "2026-12-03", "The view shows the note on its new days once it is saved.")
    }

    func testMovingATimedNoteKeepsItsTimeOfDay() async throws {
        let model = try await calendarModel()
        let isMoved = await model.reschedule(try VaultPath("Courses/Signals exam.md"), byDays: -1)
        XCTAssertTrue(isMoved)
        XCTAssertEqual(try text(at: "Courses/Signals exam.md"), "---\ncourse: Signals\ndue: 2026-12-02T09:00\n---\n", "A note without an end gets none.")
    }

    func testNotesWhoseDatesAreNotTheirOwnPropertiesDoNotMove() async throws {
        let byFormula = try await calendarModel(startDate: "formula.week_later", endDate: "note.until")
        XCTAssertFalse(byFormula.canReschedule(try VaultPath("Courses/Reading.md")))
        let isMoved = await byFormula.reschedule(try VaultPath("Courses/Reading.md"), byDays: 1)
        XCTAssertFalse(isMoved)
        XCTAssertEqual(try text(at: "Courses/Reading.md"), reading)
        XCTAssertEqual(try entries(byFormula)["Reading"]?.first, "2026-12-09", "A formula's date is still placed.")

        let embedded = try await calendarModel(embeddedIn: "Courses/Reading.md")
        XCTAssertFalse(embedded.canReschedule(try VaultPath("Courses/Reading.md")), "The note holding the base is not written from it.")
        XCTAssertTrue(embedded.canReschedule(try VaultPath("Courses/Signals exam.md")))
    }

    func testAMoveReadsTheNoteBeforeSavingSoTextWrittenElsewhereStays() async throws {
        let model = try await calendarModel()
        try write("---\ncourse: Signals\ndue: 2026-12-10\n---\nMoved in another app.\n", to: "Courses/Signals exam.md")
        let isMoved = await model.reschedule(try VaultPath("Courses/Signals exam.md"), byDays: 1)
        XCTAssertTrue(isMoved)
        XCTAssertTrue(try text(at: "Courses/Signals exam.md").hasSuffix("Moved in another app.\n"), "The body written elsewhere stays: the save reads the file first.")
    }

    // MARK: Drags and the remembered choice

    func testADragCarriesTheGrabbedDayAndThePathAndNothingElseReadsAsAnEntry() throws {
        let path = try VaultPath("Courses/Lab report: part 2.md")
        let day = try XCTUnwrap(CalendarDay(isoText: "2026-12-02"))
        let dragged = try XCTUnwrap(BaseCalendarDragPayload.entry(from: BaseCalendarDragPayload.text(path: path, grabbedDay: day)))
        XCTAssertEqual(dragged.path, path)
        XCTAssertEqual(dragged.grabbedDay, day)
        XCTAssertNil(BaseCalendarDragPayload.entry(from: "Courses/Lab report.md"))
        XCTAssertNil(BaseCalendarDragPayload.entry(from: "graphite-calendar-entry:2026-13-02:Lab.md"))
    }

    func testADropMovesTheEntryByTheDaysFromTheDayItWasPickedUpOn() async throws {
        let model = try await calendarModel()
        let result = try XCTUnwrap(model.result)
        let calendar = BaseCalendarLayout.calendar(weekStartDay: .monday)
        let entries = BaseCalendarEntry.entries(of: result, calendar: calendar)
        var moved: [(String, Int)] = []
        let moves = BaseCalendarMoves(canMove: { path in path.stem != "Reading" }, move: { path, dayOffset in moved.append((path.stem, dayOffset)) })
        let lab = try VaultPath("Courses/Lab report.md")
        let thirdDay = try XCTUnwrap(CalendarDay(isoText: "2026-12-03"))
        // The lab report spans 1 to 3 December: picked up on its last day and dropped on the 8th, it moves five days.
        let isMoved = BaseCalendarDrop.move([BaseCalendarDragPayload.text(path: lab, grabbedDay: thirdDay)], onto: try XCTUnwrap(CalendarDay(isoText: "2026-12-08")),
                                            entries: entries, moves: moves, calendar: calendar)
        XCTAssertTrue(isMoved)
        XCTAssertEqual(moved.map(\.0), ["Lab report"])
        XCTAssertEqual(moved.map(\.1), [5])
        let reading = BaseCalendarDragPayload.text(path: try VaultPath("Courses/Reading.md"), grabbedDay: thirdDay)
        let stranger = BaseCalendarDragPayload.text(path: try VaultPath("Elsewhere/Other.md"), grabbedDay: thirdDay)
        XCTAssertFalse(BaseCalendarDrop.move([reading, stranger, "plain text"], onto: try XCTUnwrap(CalendarDay(isoText: "2026-12-05")), entries: entries,
                                             moves: moves, calendar: calendar), "An entry that cannot move, another calendar's and other text move nothing.")
        XCTAssertFalse(BaseCalendarDrop.move([BaseCalendarDragPayload.text(path: lab, grabbedDay: thirdDay)], onto: thirdDay, entries: entries, moves: moves,
                                             calendar: calendar), "Dropped where it was picked up, nothing moves.")
        XCTAssertEqual(moved.count, 1)
    }

    func testEachViewRemembersItsOwnScopeAndTheOldestAreForgotten() {
        var stored = ""
        XCTAssertNil(BaseCalendarScopeMemory.scope(for: "A.base#Calendar", in: stored))
        stored = BaseCalendarScopeMemory.remembering(.week, for: "A.base#Calendar", in: stored)
        stored = BaseCalendarScopeMemory.remembering(.month, for: "B.base#Calendar", in: stored)
        XCTAssertEqual(BaseCalendarScopeMemory.scope(for: "A.base#Calendar", in: stored), .week)
        XCTAssertEqual(BaseCalendarScopeMemory.scope(for: "B.base#Calendar", in: stored), .month)
        for number in 0..<BaseCalendarScopeMemory.maximumRememberedViews { stored = BaseCalendarScopeMemory.remembering(.week, for: "\(number)", in: stored) }
        XCTAssertNil(BaseCalendarScopeMemory.scope(for: "A.base#Calendar", in: stored), "The first choice is forgotten after a hundred others.")
        XCTAssertNil(BaseCalendarScopeMemory.scope(for: "x", in: "not json"))
    }

    // MARK: Calendar Copy

    private func copySource(viewName: String = "Deadlines") throws -> CalendarCopySource {
        CalendarCopySource(vaultName: "Study", bases: BaseVaultAccess(store: store, index: index),
                           settings: CalendarCopySettings(basePath: try VaultPath("Deadlines.base"), viewName: viewName))
    }

    /// Lets the copy's tasks run for a moment.
    private func moment() async {
        _ = await XCTWaiter.fulfillment(of: [XCTestExpectation(description: "a moment")], timeout: 0.01)
    }

    /// A controller whose copied window is counted from 26 November 2026, the fixture's month.
    private func copyController(store calendarStore: FakeCalendarCopyStore, defaults: UserDefaults, clock: ManualClock = ManualClock()) -> CalendarCopyController {
        let controller = CalendarCopyController(clock: clock, store: calendarStore, defaults: defaults)
        controller.currentDate = { Date(timeIntervalSince1970: 1_795_651_200) } // 2026-11-26 UTC
        return controller
    }

    private func waitForWork(_ controller: CalendarCopyController) async throws {
        for _ in 0..<500 where controller.isWorking { await moment() }
        XCTAssertFalse(controller.isWorking)
    }

    func testACopyAddsOneEventPerNoteThenChangesOnlyWhatTheVaultChanged() async throws {
        _ = try await calendarModel()
        let calendarStore = FakeCalendarCopyStore(access: .granted)
        let defaults = try IsolatedDeviceState.make(prefix: "UiBasesCalendarTests", for: self).preferences
        let controller = copyController(store: calendarStore, defaults: defaults)
        await calendarStore.addPersonalEvent(title: "Dentist")

        controller.copyNow(try copySource())
        try await waitForWork(controller)
        guard case .copied(let firstReport, _) = controller.status else { return XCTFail("Copied: \(controller.status)") }
        XCTAssertEqual(firstReport, CalendarCopyReport(addedCount: 3))
        var events = await calendarStore.graphiteEvents()
        XCTAssertEqual(Set(events.map(\.title)), ["Lab report", "Signals exam", "Reading"])
        XCTAssertEqual(defaults.string(forKey: CalendarCopyController.calendarIdentifierKey), FakeCalendarCopyStore.calendarIdentifier)

        controller.copyNow(try copySource())
        try await waitForWork(controller)
        XCTAssertEqual(controller.status.report, CalendarCopyReport(), "A copy of an unchanged vault writes nothing.")

        try FileManager.default.removeItem(at: vault.appendingPathComponent("Courses/Reading.md"))
        try write("---\ncourse: Signals\ndue: 2026-12-04T09:00\n---\n", to: "Courses/Signals exam.md")
        _ = try await index.reconcile(root: vault)
        await calendarStore.editTitle(of: "Lab report", to: "Edited in Calendar")
        controller.copyNow(try copySource())
        try await waitForWork(controller)
        XCTAssertEqual(controller.status.report, CalendarCopyReport(changedCount: 2, removedCount: 1))
        events = await calendarStore.graphiteEvents()
        XCTAssertEqual(Set(events.map(\.title)), ["Lab report", "Signals exam"], "An edit made in Calendar is put back.")
        let personal = await calendarStore.personalEventTitles()
        XCTAssertEqual(personal, ["Dentist"], "The person's own event is never touched.")
        XCTAssertEqual(try text(at: "Courses/Lab report.md"), labReport, "No note is written.")
    }

    func testAnAutomaticCopyNeverAsksForAccessAndARefusalCopiesNothing() async throws {
        _ = try await calendarModel()
        let defaults = try IsolatedDeviceState.make(prefix: "UiBasesCalendarTests", for: self).preferences
        let clock = ManualClock()
        let unasked = FakeCalendarCopyStore(access: .notAsked, answer: .refused)
        let controller = copyController(store: unasked, defaults: defaults, clock: clock)
        controller.schedule(try copySource())
        for _ in 0..<50 where clock.pendingSleepCount == 0 { await moment() }
        clock.advance(by: CalendarCopyController.settleDelay)
        for _ in 0..<50 where controller.isCopyScheduled || controller.status == .idle { await moment() }
        try await waitForWork(controller)
        let questionCount = await unasked.questionCount
        XCTAssertEqual(questionCount, 0)
        XCTAssertEqual(controller.status.failure, CalendarCopyFailure.accessNotAsked.errorDescription)

        controller.copyNow(try copySource())
        try await waitForWork(controller)
        let questionsAfterCopyNow = await unasked.questionCount
        XCTAssertEqual(questionsAfterCopyNow, 1, "Copy Now asks once.")
        XCTAssertEqual(controller.status.failure, CalendarCopyStoreError.accessRefused.errorDescription)
        let events = await unasked.graphiteEvents()
        XCTAssertTrue(events.isEmpty)
    }

    func testAViewThatIsNotACalendarOrIsMissingIsReported() async throws {
        _ = try await calendarModel()
        let defaults = try IsolatedDeviceState.make(prefix: "UiBasesCalendarTests", for: self).preferences
        let controller = copyController(store: FakeCalendarCopyStore(access: .granted), defaults: defaults)
        controller.copyNow(try copySource(viewName: "Gone"))
        try await waitForWork(controller)
        XCTAssertEqual(controller.status.failure, CalendarCopyFailure.viewMissing(try VaultPath("Deadlines.base"), "Gone").errorDescription)
    }

    func testRemovingCopiedEventsLeavesThePersonsEventsAndKeepsACalendarThatIsNotEmpty() async throws {
        _ = try await calendarModel()
        let calendarStore = FakeCalendarCopyStore(access: .granted)
        let defaults = try IsolatedDeviceState.make(prefix: "UiBasesCalendarTests", for: self).preferences
        let controller = copyController(store: calendarStore, defaults: defaults)
        controller.copyNow(try copySource())
        try await waitForWork(controller)
        await calendarStore.addPersonalEvent(title: "Dentist")
        controller.removeCopiedEvents(vaultName: "Study")
        try await waitForWork(controller)
        XCTAssertEqual(controller.status, .removed(CalendarCopyReport(removedCount: 3), calendarRemoved: false, finishedAt: controller.status.finishedAt ?? .now))
        let remaining = await calendarStore.graphiteEvents()
        XCTAssertTrue(remaining.isEmpty)

        await calendarStore.removePersonalEvents()
        controller.removeCopiedEvents(vaultName: "Study")
        try await waitForWork(controller)
        guard case .removed(_, let calendarRemoved, _) = controller.status else { return XCTFail("Removed: \(controller.status)") }
        XCTAssertTrue(calendarRemoved, "An empty calendar goes.")
        XCTAssertNil(defaults.string(forKey: CalendarCopyController.calendarIdentifierKey))
    }

    // MARK: Calendar Copy in the workspace

    func testTurningCalendarCopyOnCopiesTheVaultsChosenBaseAfterAskingOnceAndTurningItOffStops() async throws {
        let device = try IsolatedWorkspaceDevice.make(for: self)
        let calendar = BaseDateFormatting.displayCalendar
        let today = CalendarDay(.now, in: calendar)
        let vault = try TemporaryVault.make(prefix: "CalendarCopyWorkspace", files: [
            "Courses/Lab report.md": "---\ndue: \(today.adding(days: 3, in: calendar).isoText)\n---\n",
            "Courses/Exam.md": "---\ndue: \(today.adding(days: 10, in: calendar).isoText)T09:00\n---\n",
            "Deadlines.base": "filters: file.inFolder(\"Courses\")\nviews:\n  - type: calendar\n    name: Deadlines\n    startDate: due\n",
            ".obsidian/graphite-calendar.json": #"{"copiedBase": {"file": "Deadlines.base", "view": "Deadlines"}, "taskList": "School"}"#,
        ], for: self).root
        let workspace = device.makeWorkspace()
        try await workspace.openFolderAsVault(vault)
        for _ in 0..<500 where !workspace.hasCompletedIndexScan { await moment() }
        XCTAssertFalse(workspace.preferences.isEnabled(.calendarCopy), "Off until it is turned on.")
        let questionsWhileOff = await device.calendarCopyStore.questionCount
        XCTAssertEqual(questionsWhileOff, 0)

        workspace.setCorePluginEnabled(.calendarCopy, true)
        for _ in 0..<500 where !(workspace.calendarCopy.status.report != nil) { await moment() }
        XCTAssertEqual(workspace.calendarCopy.status.report, CalendarCopyReport(addedCount: 2))
        let questions = await device.calendarCopyStore.questionCount
        XCTAssertEqual(questions, 1, "Turning it on asks for access once.")
        let titles = await device.calendarCopyStore.graphiteEvents().map(\.title).sorted()
        XCTAssertEqual(titles, ["Exam", "Lab report"])

        workspace.setCorePluginEnabled(.calendarCopy, false)
        XCTAssertFalse(workspace.calendarCopy.isWorking)
        XCTAssertFalse(workspace.calendarCopy.isCopyScheduled)
        let eventsLeft = await device.calendarCopyStore.graphiteEvents()
        XCTAssertEqual(eventsLeft.count, 2, "Turning it off leaves the calendar as it is.")
    }
}

private extension CalendarCopyController.Status {
    var report: CalendarCopyReport? {
        if case .copied(let report, _) = self { return report }
        return nil
    }

    var failure: String? {
        if case .failed(let message, _) = self { return message }
        return nil
    }

    var finishedAt: Date? {
        switch self {
        case .copied(_, let date), .removed(_, _, let date), .failed(_, let date): date
        case .idle, .copying: nil
        }
    }
}
