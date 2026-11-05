/**
 * File: SidebarAcrossTurnTests.swift
 * ----------------------------------
 * Layer: Tests
 * Description: Turning the iPad keeps the view the window showed sideways, and upright puts the sidebar away so the
 *              documents keep the window's width (HUNT-311, HUNT-317).
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 05/11/2026
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

    /// HUNT-317: upright the sidebar is put away, as Notes and Files put theirs away, and sideways it comes back as it was.
    func testTurningUprightPutsTheSidebarAwayAndSidewaysBringsItBackAsItWas() {
        let upright = GraphiteRootView.sidebarVisibility(afterTurningUpright: true, from: .automatic, keptSideways: nil)
        XCTAssertEqual(upright.shown, .detailOnly, "Upright the documents keep the window's width")
        XCTAssertEqual(upright.keptSideways, .all, "Sideways the automatic sidebar was beside the documents")
        XCTAssertEqual(GraphiteRootView.sidebarVisibility(afterTurningUpright: false, from: .detailOnly, keptSideways: upright.keptSideways).shown, .all)
        let hiddenSideways = GraphiteRootView.sidebarVisibility(afterTurningUpright: true, from: .detailOnly, keptSideways: nil)
        XCTAssertEqual(GraphiteRootView.sidebarVisibility(afterTurningUpright: false, from: .detailOnly, keptSideways: hiddenSideways.keptSideways).shown,
                       .detailOnly, "A sidebar hidden sideways stays hidden after a turn upright and back")
        XCTAssertEqual(GraphiteRootView.sidebarVisibility(afterTurningUpright: false, from: .all, keptSideways: .detailOnly).shown, .all,
                       "A sidebar shown over the documents upright is beside them sideways")
        XCTAssertEqual(GraphiteRootView.sidebarVisibility(afterTurningUpright: false, from: .detailOnly, keptSideways: nil).shown, .all,
                       "A window opened upright shows its sidebar beside the documents once sideways")
    }
}
