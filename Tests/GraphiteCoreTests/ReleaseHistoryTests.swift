/**
 * File: ReleaseHistoryTests.swift
 * -------------------------------
 * Layer: Tests
 * Description: The release history's strict grammar, its moments and build numbers, its narrowing to one
 *              device, and when a launch opens What's New.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 28/11/2026
 */

import Foundation
import GraphiteCore
import XCTest

final class ReleaseHistoryTests: XCTestCase {
    private let sampleHistory = """
    # What's New in Graphite

    ## 1.0.3

    ### 2026-11-28 14:05

    - Added: A What's New page.
    - Fixed [Mac]: Undo in a PDF works from the Edit menu.

    ### 2026-11-27

    - Changed [iPad, iPhone]: The toolbar folds into one row.

    ## 1.0.2

    ### 2026-10-23

    - Fixed: Notes save before quitting.
    """

    func testReadsVersionsGroupsAndEntriesWithKindsAndPlatforms() throws {
        let history = try ReleaseHistory.read(sampleHistory)
        XCTAssertEqual(history.versions.map(\.name), ["1.0.3", "1.0.2"])
        XCTAssertEqual(history.versions[0].groups.map(\.heading), ["2026-11-28 14:05", "2026-11-27"])
        XCTAssertEqual(history.versions[0].groups[0].entries, [
            ReleaseNoteEntry(kind: .added, text: "A What's New page."),
            ReleaseNoteEntry(kind: .fixed, platforms: [.mac], text: "Undo in a PDF works from the Edit menu.")
        ])
        XCTAssertEqual(history.versions[0].groups[1].entries[0].platforms, [.iPad, .iPhone])
        XCTAssertEqual(history.versions[0].groups[1].day, DateComponents(year: 2026, month: 11, day: 27))
        XCTAssertNil(history.versions[0].groups[1].dayAndTime, "a date alone shows no time")
        XCTAssertEqual(history.versions[0].groups[0].dayAndTime, DateComponents(year: 2026, month: 11, day: 28, hour: 14, minute: 5))
    }

    func testADateWithoutATimeIsTheLastMinuteOfItsDayAndOrdersWithBuildNumbers() throws {
        let history = try ReleaseHistory.read(sampleHistory)
        let dayOnlyGroup = history.versions[0].groups[1]
        XCTAssertEqual(dayOnlyGroup.moment, ReleaseMoment(buildNumber: "20261127.2359"))
        // A build archived on the same day, earlier, sees that day's group as new rather than hidden.
        XCTAssertLessThan(try XCTUnwrap(ReleaseMoment(buildNumber: "20261127.1236")), dayOnlyGroup.moment)
        XCTAssertEqual(history.versions[0].groups[0].moment, ReleaseMoment(buildNumber: "20261128.1405"))
    }

    func testBuildNumbersReadWithOrWithoutTheTimesLeadingZeros() {
        XCTAssertEqual(ReleaseMoment(buildNumber: "20261105.5"), ReleaseMoment(buildNumber: "20261105.0005"))
        XCTAssertNil(ReleaseMoment(buildNumber: "1"), "a development build has no moment")
        XCTAssertNil(ReleaseMoment(buildNumber: "20261305.1200"), "month 13")
        XCTAssertNil(ReleaseMoment(buildNumber: "20261105.2460"), "minute 60")
        XCTAssertNil(ReleaseMoment(buildNumber: "2026110.1200"))
    }

    func testNarrowingToADeviceKeepsItsLinesAndDropsGroupsAndVersionsLeftEmpty() throws {
        let history = try ReleaseHistory.read(sampleHistory)
        let onTheMac = history.applying(to: .mac)
        XCTAssertEqual(onTheMac.versions.map(\.name), ["1.0.3", "1.0.2"])
        XCTAssertEqual(onTheMac.versions[0].groups.map(\.heading), ["2026-11-28 14:05"], "the iPad and iPhone group is gone")
        XCTAssertEqual(onTheMac.versions[0].groups[0].entries.count, 2)
        let onTheIPad = history.applying(to: .iPad)
        XCTAssertEqual(onTheIPad.versions[0].groups[0].entries.map(\.kind), [.added], "the Mac line is gone")
        XCTAssertEqual(onTheIPad.versions[0].groups[1].entries.count, 1)
    }

    func testMalformedLinesAreRefusedWithTheirLineNumber() {
        assertRefused("# T\n## 1.0\n### 2026-11-28\n- Removed: Something.", lineNumber: 4, mentioning: "Removed")
        assertRefused("# T\n## 1.0\n### 2026-11-28\n- Fixed [Watch]: Something.", lineNumber: 4, mentioning: "Watch")
        assertRefused("# T\n## 1.0\n### 2026-11-28\n- Fixed [Mac, Mac]: Something.", lineNumber: 4, mentioning: "twice")
        assertRefused("# T\n## 1.0\n### 2026-11-28\n- Fixed something.", lineNumber: 4, mentioning: ":")
        assertRefused("# T\n## 1.0\n### 2026-11-28\n- Fixed:  ", lineNumber: 4, mentioning: "nothing")
        assertRefused("# T\n## 1.0\n### 28/11/2026\n- Fixed: Something.", lineNumber: 3, mentioning: "28/11/2026")
        assertRefused("# T\n## 1.0\n### 2026-11-28 9:05\n- Fixed: Something.", lineNumber: 3, mentioning: "9:05")
        assertRefused("# T\n## version one\n### 2026-11-28\n- Fixed: Something.", lineNumber: 2, mentioning: "version one")
        assertRefused("# T\n## 1.0\nSome prose.\n", lineNumber: 3, mentioning: "heading")
        assertRefused("# T\n### 2026-11-28\n- Fixed: Something.", lineNumber: 2, mentioning: "version")
        assertRefused("# T\n## 1.0\n- Fixed: Something.", lineNumber: 3, mentioning: "date")
    }

    func testEmptyVersionsAndGroupsAreRefused() {
        assertRefused("# T\n## 1.0.1\n## 1.0\n### 2026-11-28\n- Fixed: Something.", lineNumber: 2, mentioning: "1.0.1")
        assertRefused("# T\n## 1.0\n### 2026-11-28\n### 2026-11-27\n- Fixed: Something.", lineNumber: 3, mentioning: "no lines")
    }

    func testGroupsGoNewestFirstThroughTheWholeFileWithOneGroupPerHeading() {
        assertRefused("# T\n## 1.0\n### 2026-11-27\n- Fixed: A.\n### 2026-11-28\n- Fixed: B.", lineNumber: 5, mentioning: "newest first")
        assertRefused("# T\n## 1.0.1\n### 2026-11-27\n- Fixed: A.\n## 1.0\n### 2026-11-28\n- Fixed: B.", lineNumber: 6, mentioning: "newest first")
        assertRefused("# T\n## 1.0\n### 2026-11-27\n- Fixed: A.\n### 2026-11-27\n- Fixed: B.", lineNumber: 5, mentioning: "one per heading")
        assertRefused("# T\n## 1.0\n### 2026-11-27\n- Fixed: A.\n## 1.0\n### 2026-11-26\n- Fixed: B.", lineNumber: 5, mentioning: "twice")
    }

    private func assertRefused(_ markdown: String, lineNumber: Int, mentioning reasonPart: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try ReleaseHistory.read(markdown), file: file, line: line) { error in
            guard let formatError = error as? ReleaseHistoryFormatError else { return XCTFail("\(error)", file: file, line: line) }
            XCTAssertEqual(formatError.lineNumber, lineNumber, formatError.reason, file: file, line: line)
            XCTAssertTrue(formatError.reason.contains(reasonPart), formatError.reason, file: file, line: line)
        }
    }
}

final class WhatsNewScheduleTests: XCTestCase {
    private let history = ReleaseHistory(versions: [ReleaseNoteVersion(name: "1.0.3", groups: [
        ReleaseNoteGroup(heading: "2026-11-28 14:05", moment: ReleaseMoment(buildNumber: "20261128.1405")!, entries: [ReleaseNoteEntry(kind: .added, text: "A.")]),
        ReleaseNoteGroup(heading: "2026-11-20 10:00", moment: ReleaseMoment(buildNumber: "20261120.1000")!, entries: [ReleaseNoteEntry(kind: .fixed, text: "B.")])
    ])])

    func testAnUpdateOpensItWithTheGroupsSinceTheBuildLastSeenMarkedNew() {
        XCTAssertEqual(WhatsNewAtLaunch.decide(currentBuild: "20261128.1500", lastShownBuild: "20261121.0900", hasSeenWelcomeTour: true, history: history),
                       .show(newSince: ReleaseMoment(buildNumber: "20261121.0900")))
    }

    func testTheSameBuildAgainOpensNothing() {
        XCTAssertEqual(WhatsNewAtLaunch.decide(currentBuild: "20261128.1500", lastShownBuild: "20261128.1500", hasSeenWelcomeTour: true, history: history), .nothing)
    }

    func testANewInstallRecordsTheBuildAndLeavesTheFirstLaunchToTheWelcomeTour() {
        XCTAssertEqual(WhatsNewAtLaunch.decide(currentBuild: "20261128.1500", lastShownBuild: nil, hasSeenWelcomeTour: false, history: history), .recordSilently)
    }

    func testAnUpdateFromBeforeWhatsNewExistedOpensItWithNothingMarked() {
        XCTAssertEqual(WhatsNewAtLaunch.decide(currentBuild: "20261128.1500", lastShownBuild: nil, hasSeenWelcomeTour: true, history: history), .show(newSince: nil))
    }

    func testAnUpdateWithNoLineForThisDeviceRecordsTheBuildSilently() {
        XCTAssertEqual(WhatsNewAtLaunch.decide(currentBuild: "20261128.1600", lastShownBuild: "20261128.1500", hasSeenWelcomeTour: true, history: history), .recordSilently)
        XCTAssertEqual(WhatsNewAtLaunch.decide(currentBuild: "20261128.1600", lastShownBuild: nil, hasSeenWelcomeTour: true, history: ReleaseHistory(versions: [])), .recordSilently)
    }

    func testABuildWithoutANumberOpensNothing() {
        XCTAssertEqual(WhatsNewAtLaunch.decide(currentBuild: nil, lastShownBuild: nil, hasSeenWelcomeTour: true, history: history), .nothing)
    }
}
