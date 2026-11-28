/**
 * File: WhatsNewTests.swift
 * -------------------------
 * Layer: Tests
 * Description: The release history this build bundles reads in full and lists something on every device,
 *              and the What's New page draws it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 28/11/2026
 */

import GraphiteCore
import SwiftUI
import XCTest
@testable import GraphiteUI

@MainActor
final class WhatsNewTests: XCTestCase {
    /// ReleaseNotes.md as bundled: a line the grammar refuses fails here rather than emptying the page.
    func testTheBundledReleaseNotesReadInFullAndListSomethingOnEveryDevice() throws {
        let history = try ReleaseHistory.readBundled()
        XCTAssertFalse(history.versions.isEmpty)
        for platform in ReleaseNotePlatform.allCases {
            XCTAssertFalse(history.applying(to: platform).versions.isEmpty, "nothing listed for \(platform)")
        }
        XCTAssertEqual(ReleaseHistory.bundledForThisDevice, history.applying(to: .thisDevice))
    }

    func testThePageDrawsTheBundledHistoryWithGroupsMarkedNew() throws {
        let history = try ReleaseHistory.readBundled().applying(to: .thisDevice)
        let olderMoment = try XCTUnwrap(history.versions.last?.groups.last?.moment)
        let renderer = ImageRenderer(content: WhatsNewPage(history: history, newSince: olderMoment).frame(width: 600, height: 800))
        XCTAssertNotNil(renderer.cgImage, "the page draws")
    }
}
