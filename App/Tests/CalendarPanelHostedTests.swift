/**
 * File: CalendarPanelHostedTests.swift
 * ------------------------------------
 * Layer: Tests
 * Description: The sidebar's calendar panel in the iPad's window, over Calendar and Reminders that answer as each test
 *              sets them up: a segment of the panels' row, the month with its daily notes marked, events shown once the
 *              person chooses to, a day's note opened from the month, and Settings › Calendar.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

#if os(iOS)
import XCTest
import SwiftUI
import GraphiteCore
import GraphiteApple
@testable import GraphiteUI

/// The whole window on the iPad simulator, found by what an assistive technology reads. No test here asks for the
/// simulator's calendar access or reads its calendars: the device's store is `FakeCalendarStore`. Nothing plays sound.
@MainActor
final class CalendarPanelHostedTests: SettingsHostedTestCase {
    private var calendar: Calendar { .autoupdatingCurrent }
    private var today: CalendarDay { CalendarDay(.now, in: calendar) }

    /// A day of this month other than today, so both marks show in the month the panel opens on.
    private var otherDayThisMonth: CalendarDay { CalendarDay(year: today.year, month: today.month, day: today.day == 1 ? 2 : 1) }

    private func openWorkspace() async throws -> WorkspaceModel {
        let files = [".obsidian/daily-notes.json": #"{"folder": "Daily"}"#, "Daily/\(today.isoText).md": "# Today\n",
                     "Daily/\(otherDayThisMonth.isoText).md": "# Earlier\n", "Courses/Lecture.md": "Notes.\n"]
        let vault = try TemporaryVault.make(prefix: "CalendarPanelHosted", files: files, for: self).root
        device.defaults.set(SidebarPanel.calendar.rawValue, forKey: SidebarPanelSettingKey.panel)
        let workspace = device.makeWorkspace()
        try await workspace.openFolderAsVault(vault)
        try await waitUntil("the vault is indexed") { workspace.hasCompletedIndexScan }
        return workspace
    }

    private func todaysEvents() throws -> [CalendarEvent] {
        func time(_ hour: Int, _ minute: Int = 0) throws -> Date {
            try XCTUnwrap(calendar.date(from: DateComponents(year: today.year, month: today.month, day: today.day, hour: hour, minute: minute)))
        }
        return [
            CalendarEvent(id: "lecture", calendarTitle: "Courses", title: "Computer Architecture", startDate: try time(10, 15), endDate: try time(12),
                          location: "ETZ E 6"),
            CalendarEvent(id: "lab", calendarTitle: "Courses", title: "VLSI Lab", startDate: try time(14), endDate: try time(17), location: "ETZ J 9"),
        ]
    }

    private func showWindow(of workspace: WorkspaceModel, size: CGSize = CGSize(width: 1180, height: 820)) async throws -> UIViewController {
        let controller = try host(GraphiteRootView(workspace: workspace), size: size, horizontalSizeClass: .regular)
        let showSidebar = try await element(in: controller, "Show Sidebar") { object in object.accessibilityLabel == "Show Sidebar" }
        await follow(showSidebar)
        return controller
    }

    private func attachScreenshot(named name: String) {
        guard let window else { return }
        let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func isDayCell(_ object: NSObject, _ day: CalendarDay) -> Bool {
        guard let label = object.accessibilityLabel, let date = day.startDate(in: calendar) else { return false }
        return label.contains(date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
    }

    func testTheCalendarIsASegmentOfThePanelsRowAndMarksTheDaysThatHaveADailyNoteWithoutAskingForCalendarAccess() async throws {
        let workspace = try await openWorkspace()
        let controller = try await showWindow(of: workspace)

        let todayCell = try await element(in: controller, "today's day, marked as having a daily note") { object in
            self.isDayCell(object, self.today) && (object.accessibilityLabel ?? "").hasPrefix("Today, ") && (object.accessibilityLabel ?? "").hasSuffix(", daily note")
        }
        _ = try await element(in: controller, "the other day with a daily note") { object in
            self.isDayCell(object, self.otherDayThisMonth) && (object.accessibilityLabel ?? "").hasSuffix(", daily note")
        }
        _ = try await element(in: controller, "the Calendar segment of the panels' row") { object in
            object.accessibilityLabel == "Calendar" && object.accessibilityTraits.contains(.selected)
        }
        _ = try await element(in: controller, "the offer to show events") { object in object.accessibilityLabel == "Show Events from Calendar" }
        XCTAssertTrue(todayCell.accessibilityTraits.contains(.selected), "The panel opens on today.")
        XCTAssertGreaterThan(todayCell.accessibilityFrame.width, 30, "Seven days fit the sidebar with room for a finger.")
        XCTAssertEqual(device.calendarStore.accessRequestCount, 0, "Showing the panel never asks for calendar access.")
        XCTAssertEqual(device.calendarStore.readCount, 0, "Nothing of the calendars is read before the person allows it.")
        attachScreenshot(named: "Calendar panel, landscape")
    }

    func testShowingEventsAsksOnceThenListsTheDaysEventsAndChoosingOneMakesItsNote() async throws {
        device.calendarStore.events = try todaysEvents()
        let workspace = try await openWorkspace()
        let controller = try await showWindow(of: workspace)

        let showEvents = try await element(in: controller, "the offer to show events") { object in object.accessibilityLabel == "Show Events from Calendar" }
        await follow(showEvents)
        let lecture = try await element(in: controller, "today's first event") { object in (object.accessibilityLabel ?? "").contains("Computer Architecture") }
        _ = try await element(in: controller, "today's second event") { object in (object.accessibilityLabel ?? "").contains("VLSI Lab") }
        XCTAssertEqual(device.calendarStore.accessRequestCount, 1)
        attachScreenshot(named: "Calendar panel with today's events")

        await follow(lecture)
        try await waitUntil("the event's note opens") { workspace.selection?.rawValue == "\(self.today.isoText) Computer Architecture.md" }
        let note = try XCTUnwrap(workspace.markdownSession?.text)
        XCTAssertTrue(note.hasPrefix("---\ndate: \(today.isoText)\nstart: "), note)
        XCTAssertTrue(note.contains("location: ETZ E 6\ncalendar: Courses\n---\n\n# Computer Architecture\n"), note)
        attachScreenshot(named: "The event's note beside the calendar")
    }

    func testChoosingADayOfTheMonthOpensItsDailyNoteAndThePortraitSidebarKeepsTheWholeRow() async throws {
        let workspace = try await openWorkspace()
        let controller = try await showWindow(of: workspace, size: CGSize(width: 820, height: 1180))

        let otherDay = try await element(in: controller, "the other day with a note") { object in self.isDayCell(object, self.otherDayThisMonth) }
        await follow(otherDay)
        try await waitUntil("the day's daily note opens") { workspace.selection?.rawValue == "Daily/\(self.otherDayThisMonth.isoText).md" }
        _ = try await element(in: controller, "the Calendar segment") { object in object.accessibilityLabel == "Calendar" }
        let segmentLabels = ["Files", "Tags", "Properties", "Bookmarks", "Calendar"]
        for label in segmentLabels {
            let segment = try await element(in: controller, "the \(label) segment") { object in
                object.accessibilityLabel == label && object.accessibilityTraits.contains(.button)
            }
            XCTAssertGreaterThan(segment.accessibilityFrame.width, 24, "\(label) keeps room for a finger in the row.")
        }
        attachScreenshot(named: "Calendar panel, portrait, a past day chosen")
    }

    func testSettingsCalendarAsksForAccessOnlyWhenAllowIsChosenAndListsTheCalendars() async throws {
        device.calendarStore.eventCalendars = [CalendarList(id: "courses", title: "Courses"), CalendarList(id: "work", title: "Work")]
        let workspace = try await openWorkspace()
        let controller = try host(NavigationStack { CalendarSettingsPage(actions: workspace.calendarSettingsActions()) })

        let allow = try await element(in: controller, "the Allow button of Calendars") { object in object.accessibilityLabel == "Calendars, Allow…" }
        XCTAssertEqual(device.calendarStore.accessRequestCount, 0)
        await follow(allow)
        _ = try await element(in: controller, "a calendar's folder field") { object in (object.accessibilityLabel ?? "").contains("Courses") }
        XCTAssertEqual(device.calendarStore.accessRequestCount, 1)
        attachScreenshot(named: "Settings › Calendar after allowing Calendars")
    }
}
#endif
