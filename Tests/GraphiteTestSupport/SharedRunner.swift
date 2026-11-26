/**
 * File: SharedRunner.swift
 * ------------------------
 * Layer: Tests
 * Description: What a package test does differently on GitHub's shared virtual Macs, which run several times slower
 *              and unevenly: a timing budget is printed instead of checked, and a wait for the window is given longer.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */
import Foundation
import XCTest

/// The CI job `swift-test-macos` sets `GRAPHITE_SHARED_RUNNER=1`; a run on the development Mac sets nothing and checks every
/// budget. A budget chosen on the development Mac (a move of the eraser under 4 ms, a whole-vault base under 1.5 s) failed on
/// every CI run since 2026-11-04 while the code was correct (13.5 ms and 2.4 s there), so on the runner the test still
/// checks what the work produced and only prints its time (testing.md T-32: time belongs on the development machine).
public enum SharedRunner {
    public static let variableName = "GRAPHITE_SHARED_RUNNER"

    /// True on GitHub's shared runners.
    public static var isActive: Bool {
        ProcessInfo.processInfo.environment[variableName] == "1"
    }

    /// How many times longer a test waits for the window there: windows on the runner laid out and loaded their embeds
    /// several times slower than on the development Mac (a release-vault pass took 160 s there).
    public static var waitScale: Double {
        isActive ? 4 : 1
    }

    /// Checks `measured < budget` on the development Mac; on a shared runner prints both, so the log still shows the time.
    public static func assertWithinTimingBudget<Value: Comparable>(_ measured: Value, isLessThan budget: Value, _ message: @autoclosure () -> String = "",
                                                                   file: StaticString = #filePath, line: UInt = #line) {
        guard isActive else {
            XCTAssertLessThan(measured, budget, message(), file: file, line: line)
            return
        }
        print("TIMING-BUDGET not checked on a shared runner: \(measured), budget \(budget). \(message())")
    }
}
