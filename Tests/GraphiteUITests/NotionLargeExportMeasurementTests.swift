/**
 * File: NotionLargeExportMeasurementTests.swift
 * ---------------------------------------------
 * Layer: Tests
 * Description: A large Notion export imported through the workspace as the app imports it, with its time, the process's
 *              peak memory and how late the main actor answered meanwhile.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 27/11/2026
 */

import XCTest
import Darwin
import GraphiteCore
import GraphiteIndex
import GraphiteApple
import GraphiteTestSupport
@testable import GraphiteUI

/// Docs/Notion-import-todo.md, section 8: the measurement of a large import. A made-up export of about 10,000 pages and
/// over a gigabyte (`scripts`-free: made in a scratch folder, never committed) is named by `GRAPHITE_NOTION_LARGE_EXPORT`
/// (its zip, or several zips separated by commas). The test returns at once without it. With it, the export is imported
/// through `WorkspaceModel.importNotionExport` into a vault with an index, as Import from Notion does, while a sampler
/// reads the process's memory footprint every 100 ms and the main actor is asked to run every 16 ms: how late those runs
/// come is how long the app would not answer a key or a Pencil stroke. The numbers are printed on a `NOTION-LARGE` line.
@MainActor
final class NotionLargeExportMeasurementTests: XCTestCase {
    static let exportVariable = "GRAPHITE_NOTION_LARGE_EXPORT"

    func testTheLargeExportImportsWhileTheMainActorKeepsAnswering() async throws {
        guard let names = ProcessInfo.processInfo.environment[Self.exportVariable], !names.isEmpty else {
            return print("Not run: \(Self.exportVariable) names no export.")
        }
        let sources = names.split(separator: ",").map { name in URL(fileURLWithPath: String(name)) }
        let vault = try TemporaryVault.make(prefix: "NotionLargeExport", for: self).root
        let indexFolder = try TemporaryVault.make(prefix: "NotionLargeExportIndex", for: self).root
        let index = try VaultIndex(databaseURL: indexFolder.appendingPathComponent("index.sqlite"))
        _ = try await index.reconcile(root: vault)
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: vault)
        workspace.store = VaultStore(root: vault)
        workspace.index = index
        workspace.hasCompletedIndexScan = true

        let memoryAtStart = Self.memoryFootprintBytes()
        let peakMemory = PeakMemorySampler()
        let sampling = Task.detached(priority: .high) { await peakMemory.sampleUntilCancelled() }
        let started = ContinuousClock.now
        XCTAssertTrue(workspace.importNotionExport(sources, into: .root))
        let clock = ContinuousClock()
        var latenesses: [Duration] = []
        var lastProgress = NotionImportProgress()
        while true {
            if case .finished = workspace.notionImport?.state { break }
            if case .importing(let progress, _, _)? = workspace.notionImport?.state { lastProgress = progress }
            let asked = ContinuousClock.now
            try await clock.sleep(for: .milliseconds(16))
            latenesses.append(ContinuousClock.now - asked - .milliseconds(16))
            XCTAssertLessThan(ContinuousClock.now - started, .seconds(3_600), "The import ended within an hour.")
        }
        let elapsed = ContinuousClock.now - started
        sampling.cancel()
        let peak = await peakMemory.peakBytes
        guard case .finished(let summary)? = workspace.notionImport?.state else { return XCTFail("The import did not end.") }
        workspace.endNotionImport()
        let sortedLatenesses = latenesses.sorted()
        func milliseconds(_ duration: Duration) -> Int { Int(duration / .milliseconds(1)) }
        let late99 = sortedLatenesses.isEmpty ? .zero : sortedLatenesses[Int(Double(sortedLatenesses.count - 1) * 0.99)]
        let overFifty = latenesses.filter { lateness in lateness > .milliseconds(50) }.count
        print("NOTION-LARGE pages=\(lastProgress.pageCount) notes=\(summary.noteCount) bases=\(summary.baseCount) attachments=\(summary.attachmentCount) "
              + "seconds=\(Int(elapsed / .seconds(1))) memoryAtStartMB=\(memoryAtStart / 1_048_576) peakMemoryMB=\(peak / 1_048_576) "
              + "mainActorLateMaxMs=\(milliseconds(sortedLatenesses.last ?? .zero)) mainActorLate99Ms=\(milliseconds(late99)) "
              + "mainActorChecks=\(latenesses.count) over50Ms=\(overFifty) failure=\(summary.failureMessage ?? "none")")
        XCTAssertNil(summary.failureMessage)
        XCTAssertGreaterThan(summary.noteCount, 9_000)
    }

    /// The process's memory footprint, as Activity Monitor and Xcode's gauge show it.
    nonisolated static func memoryFootprintBytes() -> UInt64 {
        var information = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &information) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &count) }
        }
        return result == KERN_SUCCESS ? information.phys_footprint : 0
    }
}

/// The highest memory footprint read every 100 ms until the task reading it is cancelled.
private actor PeakMemorySampler {
    private(set) var peakBytes: UInt64 = 0

    func sampleUntilCancelled() async {
        while !Task.isCancelled {
            peakBytes = max(peakBytes, NotionLargeExportMeasurementTests.memoryFootprintBytes())
            try? await ContinuousClock().sleep(for: .milliseconds(100))
        }
    }
}
