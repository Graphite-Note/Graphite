/**
 * File: ViewSwitchingHostedTests.swift
 * ------------------------------------
 * Layer: Tests
 * Description: Switching the iPad's whole window between Library and List leaves the main thread free.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

#if os(iOS)
import XCTest
import GraphiteCore
@testable import GraphiteUI

/// The window's root view on the iPad simulator over a small `OwnerShapedVault`, as `ViewSwitchingMacTests` opens it on
/// the Mac; `PerformanceBenchmarkTests.testSwitchingViewsInAVaultOfTheOwnersSize` times the switches at the owner's size.
/// Numbers are in `Docs/View-switching-speed-todo.md` section 3.
@MainActor
final class ViewSwitchingHostedTests: XCTestCase {
    /// The budget catches a freeze such as the 4.5 s the Mac's hidden Tags view took in the owner's vault.
    func testSwitchingBetweenLibraryAndListLeavesTheMainThreadFree() async throws {
        try TimingBudgets.requireTheOwnersDevice()
        let (workspace, window) = try await ViewSwitchingWindow.open(.small, for: self)
        let quietWatch = MainThreadQuietWatch(window: window)
        var measurements: [MainThreadQuietWatch.Measurement] = []
        for _ in 0..<2 {
            measurements.append(try await quietWatch.measure { workspace.preferences.library.presentation = .list })
            measurements.append(try await quietWatch.measure { workspace.preferences.library.presentation = .library })
        }
        MainThreadQuietWatch.report(scenario: "list-and-library", shape: .small, measurements: measurements)
        // Measured 2026-11-12 on the simulator (Debug, the hosted tests' build); the budget leaves room for a loaded Mac.
        for measurement in measurements {
            XCTAssertLessThan(measurement.busy, .milliseconds(3_000), "A switch kept the main thread busy \(measurement.busy).")
        }
    }
}
#endif
