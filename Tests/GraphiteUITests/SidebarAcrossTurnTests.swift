/**
 * File: SidebarAcrossTurnTests.swift
 * ----------------------------------
 * Layer: Tests
 * Description: Turning the iPad keeps the view the window showed: the sidebar beside the documents, or hidden (HUNT-311).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 04/11/2026
 */

import XCTest
import SwiftUI
@testable import GraphiteUI

/// The owner's report of 2026-11-04: upright and sideways "it's not the same view". The system's automatic sidebar is
/// beside the documents sideways and hidden upright; a turn now keeps what the window showed. Nothing here draws.
@MainActor
final class SidebarAcrossTurnTests: XCTestCase {
    func testATurnKeepsTheSidebarTheWindowShowed() {
        XCTAssertEqual(GraphiteRootView.sidebarVisibility(keptAcrossTurnOf: .automatic, wasTallerThanWide: false), .all,
                       "Sideways it was beside the documents; upright it stays there")
        XCTAssertEqual(GraphiteRootView.sidebarVisibility(keptAcrossTurnOf: .automatic, wasTallerThanWide: true), .detailOnly,
                       "Upright it was hidden; sideways it stays hidden")
    }

    func testATurnKeepsAChoiceThePersonMade() {
        // `.doubleColumn` compares equal to `.automatic` in SwiftUI, and Graphite never chooses it.
        for visibility in [NavigationSplitViewVisibility.all, .detailOnly] {
            XCTAssertEqual(GraphiteRootView.sidebarVisibility(keptAcrossTurnOf: visibility, wasTallerThanWide: true), visibility)
            XCTAssertEqual(GraphiteRootView.sidebarVisibility(keptAcrossTurnOf: visibility, wasTallerThanWide: false), visibility)
        }
    }

    func testTheSidebarButtonStillShowsAndHidesItAfterATurn() {
        let keptUpright = GraphiteRootView.sidebarVisibility(keptAcrossTurnOf: .automatic, wasTallerThanWide: false)
        XCTAssertEqual(GraphiteRootView.sidebarVisibility(toggling: keptUpright, automaticHidesSidebar: true), .detailOnly)
        let keptSideways = GraphiteRootView.sidebarVisibility(keptAcrossTurnOf: .automatic, wasTallerThanWide: true)
        XCTAssertEqual(GraphiteRootView.sidebarVisibility(toggling: keptSideways, automaticHidesSidebar: false), .all)
    }
}
