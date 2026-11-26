/**
 * File: BaseCalendarViewMacTests.swift
 * ------------------------------------
 * Layer: Tests
 * Description: The calendar view of a base drawn in a Mac window: the month and week grids at a wide width, the
 *              phone's layouts at a narrow one, and pictures of each for a person to look at.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

#if os(macOS)
import AppKit
import SwiftUI
import XCTest
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI
import GraphiteTestSupport

@MainActor
final class BaseCalendarViewMacTests: XCTestCase {
    /// A result of a calendar view over notes of this month, so today's month shows them.
    private func calendarResult(weekStartDay: BaseCalendarWeekday = .monday) throws -> BaseQueryResult {
        let calendar = BaseCalendarLayout.calendar(weekStartDay: weekStartDay)
        let today = CalendarDay(.now, in: calendar)
        let monthStart = CalendarDay(year: today.year, month: today.month, day: 1)
        func dayText(_ offset: Int) -> String { monthStart.adding(days: offset, in: calendar).isoText }
        let definition = try BaseDefinition.parse("views:\n  - type: calendar\n    name: Deadlines\n    order: [file.name]\n    startDate: due\n    endDate: until\n    weekStartDay: \(weekStartDay.rawValue)\n")
        let fixtures: [(String, String)] = [
            ("Lab report.md", "due: \(dayText(2))\nuntil: \(dayText(4))"),
            ("Signals exam.md", "due: \(dayText(3))T09:00"),
            ("Reading.md", "due: \(dayText(3))"),
            ("Problem set.md", "due: \(dayText(3))"),
            ("Quiz.md", "due: \(dayText(3))"),
            ("Project week.md", "due: \(dayText(12))\nuntil: \(dayText(18))"),
            ("Today's lecture.md", "due: \(today.isoText)T10:15"),
        ]
        let records = try fixtures.map { name, yaml in
            BaseFileRecord(path: try VaultPath("Courses/" + name), size: 1, createdDate: .now, modifiedDate: .now,
                           properties: try XCTUnwrap(BaseFrontmatter.entries(fromYAML: yaml)))
        }
        return BaseQueryEngine(definition: definition, environment: BaseEvaluationEnvironment(calendar: calendar), thisRecord: nil).run(viewIndex: 0, records: records)
    }

    private var inertActions: BaseViewActions {
        BaseViewActions(openPath: { _ in }, openLink: { _ in }, editRequest: { _, _, _ in nil }, beginEditing: { _ in },
                        toggleCheckbox: { _, _ in }, requestedCheckboxValue: { _ in nil }, thumbnails: BaseThumbnailStore(),
                        vaultRoot: URL(filePath: "/Calendar test vault"), contentVersion: 0) // No picture is read.
    }

    private func hostedCalendar(_ result: BaseQueryResult, scope: BaseCalendarScope, width: CGFloat, appearance: NSAppearance.Name = .aqua) -> (NSWindow, NSHostingView<AnyView>) {
        let view = BaseCalendarView(result: result, actions: inertActions, layoutMemoryKey: "Test.base#\(scope.rawValue)",
                                    moves: BaseCalendarMoves(canMove: { _ in true }, move: { _, _ in }), editView: nil, defaultScope: scope)
            .environment(\.basesScrollVertically, false)
            .background(.background)
        let hostingView = NSHostingView(rootView: AnyView(view))
        hostingView.appearance = NSAppearance(named: appearance)
        hostingView.frame = CGRect(x: 0, y: 0, width: width, height: 900)
        let window = NSWindow(contentRect: hostingView.frame, styleMask: [.titled], backing: .buffered, defer: true)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = hostingView
        window.showInvisibly()
        hostingView.layoutSubtreeIfNeeded()
        return (window, hostingView)
    }

    func testTheMonthGridHasAWeekRowPerWeekAndTheWeekAndPhoneLayoutsLayOut() throws {
        let result = try calendarResult()
        for (scope, width) in [(BaseCalendarScope.month, 1_000.0), (.week, 1_000), (.month, 390), (.week, 390)] as [(BaseCalendarScope, CGFloat)] {
            let (window, hostingView) = hostedCalendar(result, scope: scope, width: width)
            let fittingHeight = hostingView.fittingSize.height
            XCTAssertGreaterThan(fittingHeight, 200, "\(scope) at \(width) pt lays out its grid.")
            if scope == .month, width > BaseCalendarView.compactWidthThreshold {
                let weekCount = CalendarMonth(containing: CalendarDay(.now, in: BaseCalendarLayout.calendar(weekStartDay: .monday))).weeks(in: BaseCalendarLayout.calendar(weekStartDay: .monday)).count
                XCTAssertGreaterThanOrEqual(fittingHeight, CGFloat(weekCount) * BaseCalendarMonthGrid.weekHeight, "Every week of the month has its row.")
            }
            window.orderOut(nil)
        }
    }

    /// The parts around the grid: a view without a start date, the Calendar section of Edit View and Settings › Calendar
    /// Copy, each laid out in a window.
    private func otherParts() throws -> [(name: String, view: AnyView, height: CGFloat)] {
        let withoutDates = try BaseDefinition.parse("views:\n  - type: calendar\n    name: Deadlines\n")
        let withoutDatesResult = BaseQueryEngine(definition: withoutDates, environment: BaseEvaluationEnvironment(), thisRecord: nil).run(viewIndex: 0, records: [])
        let deadlines = try BaseDefinition.parse("views:\n  - type: calendar\n    name: Deadlines\n    startDate: due\n    endDate: until\n    weekStartDay: sunday\n")
        let editor = BaseViewEditorSheet(definition: deadlines, viewIndex: 0, availablePropertyKeys: ["due", "until", "course"]) { _, _, _ in nil }
        let controller = CalendarCopyController(clock: ManualClock(), store: FakeCalendarCopyStore(access: .granted),
                                                defaults: try IsolatedDeviceState.make(prefix: "BaseCalendarViewMacTests", for: self).preferences)
        let basePath = try VaultPath("Courses/Deadlines.base")
        let chosen = CalendarCopySettings(basePath: basePath, viewName: "Calendar")
        let actions = CalendarCopySettingsActions(hasVault: true, settings: { chosen }, saveSettings: { _ in nil },
                                                  baseFiles: { [basePath] }, calendarViewNames: { _ in ["Calendar"] },
                                                  copyNow: {}, removeCopiedEvents: {})
        return [
            ("no-start-date", AnyView(BaseCalendarView(result: withoutDatesResult, actions: inertActions, layoutMemoryKey: "T",
                                                        moves: BaseCalendarMoves(canMove: { _ in false }, move: { _, _ in }), editView: {})
                .background(.background)), 420),
            ("edit-view", AnyView(editor.background(.background)), 1_300),
            ("calendar-copy-settings", AnyView(NavigationStack { CalendarCopySettingsPage(controller: controller, actions: actions) }.background(.background)), 700),
        ]
    }

    func testTheViewWithoutDatesTheEditorSectionAndTheCopySettingsLayOut() throws {
        for part in try otherParts() {
            let hostingView = NSHostingView(rootView: part.view.frame(width: 640, height: part.height))
            hostingView.frame = CGRect(x: 0, y: 0, width: 640, height: part.height)
            let window = NSWindow(contentRect: hostingView.frame, styleMask: [.titled], backing: .buffered, defer: true)
            window.contentView = hostingView
            window.showInvisibly()
            hostingView.layoutSubtreeIfNeeded()
            XCTAssertGreaterThan(hostingView.fittingSize.height, 100, part.name)
            if let folder = ProcessInfo.processInfo.environment["GRAPHITE_BASE_CALENDAR_SCREENSHOTS"] {
                let bitmap = try XCTUnwrap(hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds))
                hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: folder).appendingPathComponent(part.name + ".png"))
            }
            window.orderOut(nil)
        }
    }

    /// Writes pictures of each layout, light and dark, into the folder named in `GRAPHITE_BASE_CALENDAR_SCREENSHOTS`, for a
    /// person to look at; it checks nothing otherwise.
    func testScreenshotsOfTheLayouts() throws {
        guard let folder = ProcessInfo.processInfo.environment["GRAPHITE_BASE_CALENDAR_SCREENSHOTS"] else { return }
        let result = try calendarResult()
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            for (scope, width) in [(BaseCalendarScope.month, 1_000.0), (.week, 1_000), (.month, 390), (.week, 390)] as [(BaseCalendarScope, CGFloat)] {
                let (window, hostingView) = hostedCalendar(result, scope: scope, width: width, appearance: appearance)
                hostingView.frame.size.height = min(max(hostingView.fittingSize.height, 300), 1_400)
                window.setContentSize(hostingView.frame.size)
                hostingView.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds))
                hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
                let name = "calendar-\(appearance == .aqua ? "light" : "dark")-\(scope.rawValue)-\(Int(width)).png"
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: folder).appendingPathComponent(name))
                window.orderOut(nil)
            }
        }
    }
}

#endif
