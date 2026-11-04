/**
 * File: WorkspaceFocusModeCompactWidthTests.swift
 * -----------------------------------------------
 * Layer: Tests
 * Description: Focus is offered only where it can be seen and ended, and ends when the window turns compact.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import XCTest
import SwiftUI
@testable import GraphiteUI

/// HUNT-190: on a phone Focus changed nothing visible, yet the window held the state and
/// woke up with its sidebars hidden once it was wide again.
final class WorkspaceFocusModeCompactWidthTests: XCTestCase {
    func testFocusIsOfferedAtARegularWidthOnly() {
        XCTAssertTrue(WorkspaceFocusMode.isOffered(isCompactWidth: false))
        XCTAssertFalse(WorkspaceFocusMode.isOffered(isCompactWidth: true))
    }

    func testAWindowInFocusThatBecomesCompactLeavesFocusAndRestoresItsPanels() {
        var focusMode = WorkspaceFocusMode()
        var columnVisibility = NavigationSplitViewVisibility.all
        var showsInspector = true
        focusMode.enter(columnVisibility: &columnVisibility, showsInspector: &showsInspector)

        focusMode.widthDidChange(isCompactWidth: false, columnVisibility: &columnVisibility, showsInspector: &showsInspector)
        XCTAssertTrue(focusMode.isActive, "A wide window stays in Focus.")
        focusMode.widthDidChange(isCompactWidth: true, columnVisibility: &columnVisibility, showsInspector: &showsInspector)

        XCTAssertFalse(focusMode.isActive)
        XCTAssertEqual(columnVisibility, .all)
        XCTAssertTrue(showsInspector)
    }
}
