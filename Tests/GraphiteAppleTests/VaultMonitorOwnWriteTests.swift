/**
 * File: VaultMonitorOwnWriteTests.swift
 * -------------------------------------
 * Layer: Tests
 * Description: Graphite's own writes are not reported back to its vault monitor as other apps' changes, though macOS
 *              may report them (HUNT-368), while another write to the same file right after them still is: in place,
 *              through another coordinator, or from another process.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 18/11/2026
 */

import XCTest
import Synchronization
import GraphiteApple
import GraphiteCore
#if canImport(GraphiteTestSupport)
import GraphiteTestSupport
#endif

final class VaultMonitorOwnWriteTests: XCTestCase {
    /// How long macOS is given to report a write: its report of a coordinated write came about
    /// a second after it on macOS 27.2.1.
    private let reportWaitSeconds: TimeInterval = 2

    /// The reports heard, and whether they still come from Graphite's own writes.
    private final class ReportedChanges: Sendable {
        private let count = Mutex(0)
        private let isAfterOwnWrites = Mutex(false)
        /// Counts a report; true while only Graphite's own writes were made.
        func add() -> Bool {
            count.withLock { count in count += 1 }
            return !isAfterOwnWrites.withLock { value in value }
        }
        func ownWritesEnded() { isAfterOwnWrites.withLock { value in value = true } }
        var total: Int { count.withLock { count in count } }
    }

    func testAWriteThroughTheMonitorsWriterIsNotReportedAndAnotherWriteAfterItIs() async throws {
        let vault = try TemporaryVault.make(prefix: "VaultMonitorOwnWrite", for: self)
        let location = vault.location(of: "Note.md")
        let reported = ReportedChanges()
        let noReport = expectation(description: "Graphite's own writes are not reported")
        noReport.isInverted = true
        let monitor = VaultMonitor(root: vault.root) { changedLocation in
            guard changedLocation?.lastPathComponent == "Note.md" else { return }
            if reported.add() { noReport.fulfill() }
        }
        defer { monitor.stop() }

        let writer = AtomicFileWriter(filePresenter: monitor)
        _ = try writer.write(Data("First".utf8), to: location, expecting: .absent)
        _ = try writer.write(Data("Second".utf8), to: location, expecting: .revision(FileRevision.read(location)))
        await fulfillment(of: [noReport], timeout: reportWaitSeconds)
        XCTAssertEqual(reported.total, 0, "Graphite's own writes are not another app's change.")
        reported.ownWritesEnded()

        // The same size, written in place without Graphite's writer, as another app writes.
        try Data("Third!".utf8).write(to: location)
        try await waitUntil("the other write is reported", timeoutSeconds: 5) { reported.total > 0 }
    }

    /// A sync provider's or Obsidian's write right after Graphite's save, well within the
    /// time a save is remembered, is reported: one through another coordinator, which replaces
    /// the file, and one from another process, which writes it in place at the same size.
    func testAnOutsideWriteRightAfterGraphitesOwnIsReported() async throws {
        let vault = try TemporaryVault.make(prefix: "VaultMonitorOutsideWrite", for: self)
        let location = vault.location(of: "Note.md")
        let reported = ReportedChanges()
        let monitor = VaultMonitor(root: vault.root) { changedLocation in
            if changedLocation?.lastPathComponent == "Note.md" { _ = reported.add() }
        }
        defer { monitor.stop() }
        let writer = AtomicFileWriter(filePresenter: monitor)

        _ = try writer.write(Data("Mine 1".utf8), to: location, expecting: .absent)
        _ = try AtomicFileWriter().write(Data("Sync 1".utf8), to: location, expecting: .revision(FileRevision.read(location)))
        try await waitUntil("another coordinator's write is reported", timeoutSeconds: 5) { reported.total > 0 }

        #if os(macOS)
        let reportsBefore = reported.total
        _ = try writer.write(Data("Mine 2".utf8), to: location, expecting: .revision(FileRevision.read(location)))
        let otherProcess = Process()
        otherProcess.executableURL = URL(fileURLWithPath: "/bin/sh")
        otherProcess.arguments = ["-c", "printf 'Them 2' > \"$0\"", location.path]
        try otherProcess.run()
        otherProcess.waitUntilExit()
        XCTAssertEqual(try String(contentsOf: location, encoding: .utf8), "Them 2")
        try await waitUntil("another process's write is reported", timeoutSeconds: 5) { reported.total > reportsBefore }
        #endif
    }

    func testTheFingerprintChangesWithTheFileAndNotWithAReadingOfIt() throws {
        let vault = try TemporaryVault.make(prefix: "FileWriteFingerprint", for: self)
        let location = try vault.writeFile("Note.md", text: "First")
        let written = try XCTUnwrap(FileWriteFingerprint.read(location))
        _ = try Data(contentsOf: location)
        XCTAssertEqual(FileWriteFingerprint.read(location), written)
        _ = try AtomicFileWriter().write(Data("Other".utf8), to: location, expecting: .revision(FileRevision.read(location)))
        XCTAssertNotEqual(FileWriteFingerprint.read(location), written, "A replacement is a new file.")
        XCTAssertNil(FileWriteFingerprint.read(vault.location(of: "Missing.md")))
    }
}
