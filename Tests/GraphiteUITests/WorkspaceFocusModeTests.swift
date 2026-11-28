/**
 * File: WorkspaceFocusModeTests.swift
 * -----------------------------------
 * Layer: Tests
 * Description: Focus mode hides and restores the panels, and where a document's Write, Undo and Redo go as the
 *              documents area narrows on the iPad and the Mac.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 28/11/2026
 */

import XCTest
import SwiftUI
@testable import GraphiteUI

final class WorkspaceFocusModeTests: XCTestCase {
    func testFocusRestoresEachPreviousPanelArrangement() {
        for originalVisibility in [NavigationSplitViewVisibility.automatic, .all, .detailOnly] {
            for originalInspector in [false, true] {
                var focusMode = WorkspaceFocusMode()
                var columnVisibility = originalVisibility
                var showsInspector = originalInspector
                focusMode.enter(columnVisibility: &columnVisibility, showsInspector: &showsInspector)
                XCTAssertTrue(focusMode.isActive)
                XCTAssertEqual(columnVisibility, .detailOnly)
                XCTAssertFalse(showsInspector)
                // A repeated request must not replace the saved layout with the hidden layout.
                focusMode.enter(columnVisibility: &columnVisibility, showsInspector: &showsInspector)
                focusMode.leave(columnVisibility: &columnVisibility, showsInspector: &showsInspector)
                XCTAssertFalse(focusMode.isActive)
                XCTAssertEqual(columnVisibility, originalVisibility)
                XCTAssertEqual(showsInspector, originalInspector)
            }
        }
    }

    /// Write, Undo and Redo leave a wide window's toolbar before iPadOS would hide them in
    /// its overflow menu; a compact width keeps them in its navigation bar, which holds
    /// nothing else.
    func testDocumentControlsMoveBelowTheToolbarWhenTheDocumentsAreaIsNarrow() {
        let threshold = DocumentToolbarLayout.minimumDetailWidthForToolbarControls
        XCTAssertFalse(DocumentToolbarLayout.usesControlRow(detailWidth: 1_376, horizontalSizeClass: .compact, toolbar: .iPad), "A compact width keeps them in the navigation bar")
        XCTAssertTrue(DocumentToolbarLayout.usesControlRow(detailWidth: 1_032, horizontalSizeClass: .regular, toolbar: .iPad), "iPad portrait")
        XCTAssertTrue(DocumentToolbarLayout.usesControlRow(detailWidth: threshold - 1, horizontalSizeClass: .regular, toolbar: .iPad))
        XCTAssertFalse(DocumentToolbarLayout.usesControlRow(detailWidth: threshold, horizontalSizeClass: .regular, toolbar: .iPad))
        XCTAssertFalse(DocumentToolbarLayout.usesControlRow(detailWidth: 1_376, horizontalSizeClass: .regular, toolbar: .iPad), "iPad landscape without the sidebar")
        XCTAssertFalse(DocumentToolbarLayout.usesControlRow(detailWidth: nil, horizontalSizeClass: .regular, toolbar: .iPad), "Not measured yet")
    }

    /// The Mac's toolbar has no Undo and Redo and holds Write whole in a narrower documents area, so the right sidebar
    /// beside a note in a window of 1,440 points no longer moves Write out of it.
    func testTheMacsToolbarKeepsWriteInANarrowerDocumentsArea() {
        XCTAssertFalse(DocumentToolbarLayout.usesControlRow(detailWidth: 840, horizontalSizeClass: .regular, toolbar: .mac), "1,440 points with both sidebars")
        XCTAssertTrue(DocumentToolbarLayout.usesControlRow(detailWidth: 840, horizontalSizeClass: .regular, toolbar: .iPad))
        XCTAssertTrue(DocumentToolbarLayout.usesControlRow(detailWidth: 520, horizontalSizeClass: .regular, toolbar: .mac), "Where Write went to the overflow menu")
        #if os(macOS)
        XCTAssertEqual(DocumentToolbarLayout.Toolbar.current, .mac)
        #endif
    }

    func testLeavingInactiveFocusDoesNotChangePanels() {
        var focusMode = WorkspaceFocusMode()
        var columnVisibility = NavigationSplitViewVisibility.all
        var showsInspector = true
        focusMode.leave(columnVisibility: &columnVisibility, showsInspector: &showsInspector)
        XCTAssertEqual(columnVisibility, .all)
        XCTAssertTrue(showsInspector)
    }
}
